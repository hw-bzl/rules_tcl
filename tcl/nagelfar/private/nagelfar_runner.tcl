# Nagelfar runner for rules_tcl.
#
# Supports two modes:
#   1. Direct invocation (aspect): args passed on argv
#   2. Args-file mode (test): RULES_TCL_NAGELFAR_ARGS_FILE or
#      RULES_TCL_LINT_ARGS_FILE env var points to an rlocationpath
#      whose contents are the args (one per line).
#
# Always runs `nagelfar -header` first over the target `--src` files to
# aggregate their proc/namespace shapes into a syntaxdb. The output path
# comes from `--header-output` when provided; otherwise the runner
# constructs `$TEST_UNDECLARED_OUTPUTS_DIR/syntaxdb.tcl` so `bazel test`
# picks it up under `test.outputs/outputs.zip`. If neither is available,
# it's a configuration error and the runner exits.
#
# Silence behavior is decided by `$BAZEL_TEST` (set by Bazel on test
# actions). When the env var is present the runner flushes each pass's
# output to stderr as soon as the pass finishes; otherwise (build/aspect
# actions) it stays quiet and only dumps the full log on non-zero exit.

package require runfiles

# Normalize argv so `--flag=value` becomes two tokens `--flag value`, so
# the caller only has to handle the second form.
proc split_equals {argv} {
    set out {}
    foreach arg $argv {
        set eq [string first "=" $arg]
        if {[string match "--*" $arg] && $eq >= 0} {
            lappend out [string range $arg 0 [expr {$eq - 1}]] \
                [string range $arg [expr {$eq + 1}] end]
        } else {
            lappend out $arg
        }
    }
    return $out
}

# Resolve `value` through the runfiles helper when runfiles are in use;
# otherwise pass through unchanged.
proc rloc {value use_runfiles r} {
    if {$use_runfiles} {
        return [runfiles::rlocation $r $value]
    }
    return $value
}

proc parse_args {argv use_runfiles r} {
    set srcs {}
    set dep_srcs {}
    set nagelfar_path ""
    set syntaxdbs {}
    set extra_args {}
    set header_output ""

    set argv [split_equals $argv]
    set n [llength $argv]
    set i 0
    while {$i < $n} {
        set arg [lindex $argv $i]
        set next [expr {$i + 1 < $n ? [lindex $argv [expr {$i + 1}]] : ""}]
        switch -- $arg {
            "--src" {lappend srcs [rloc $next $use_runfiles $r]; incr i}
            "--dep-src" {lappend dep_srcs [rloc $next $use_runfiles $r]; incr i}
            "--nagelfar" {set nagelfar_path [rloc $next $use_runfiles $r]; incr i}
            "--syntaxdb" {lappend syntaxdbs [rloc $next $use_runfiles $r]; incr i}
            "--nagelfar-arg" {lappend extra_args $next; incr i}
            "--header-output" {set header_output $next; incr i}
        }
        incr i
    }

    return [list $srcs $dep_srcs $nagelfar_path $syntaxdbs $extra_args $header_output]
}

# Run `nagelfar` under the ambient tclsh, returning
# [list exit_code merged_stdout_and_stderr].
proc run_nagelfar {tclsh nagelfar_path cmd_args} {
    set cmd [list $tclsh $nagelfar_path {*}$cmd_args]
    set exit_code [catch {exec {*}$cmd 2>@1} output]
    return [list $exit_code $output]
}

# Flush a captured pass to stderr, appending a trailing newline if the
# output didn't already end with one. No-op when `str` is empty.
proc flush_stream {str} {
    if {$str eq ""} {return}
    puts -nonewline stderr $str
    if {[string index $str end] ne "\n"} {puts stderr ""}
}

set use_runfiles 0
set r ""
set effective_argv $::argv

foreach env_key {RULES_TCL_NAGELFAR_ARGS_FILE RULES_TCL_LINT_ARGS_FILE} {
    if {[info exists ::env($env_key)]} {
        set use_runfiles 1
        set r [runfiles::create]
        set args_rloc $::env($env_key)
        set args_path [runfiles::rlocation $r $args_rloc]
        set fh [open $args_path r]
        set content [read $fh]
        close $fh
        set effective_argv {}
        foreach line [split $content "\n"] {
            set line [string trim $line]
            if {$line ne ""} {
                lappend effective_argv $line
            }
        }
        break
    }
}

lassign [parse_args $effective_argv $use_runfiles $r] \
    srcs dep_srcs nagelfar_path syntaxdbs extra_args header_output

if {$nagelfar_path eq ""} {
    puts stderr "Error: --nagelfar is required"
    exit 1
}
if {[llength $srcs] == 0} {
    puts stderr "Error: at least one --src is required"
    exit 1
}

# Bazel sets BAZEL_TEST=1 on test actions; use its presence to flush each
# pass's output as soon as it completes.
set streaming [info exists ::env(BAZEL_TEST)]

# Resolve where the header syntaxdb should land. --header-output wins
# when explicit; otherwise fall back to the test-artifacts dir so the
# file is packaged into `test.outputs/`.
if {$header_output eq ""} {
    if {[info exists ::env(TEST_UNDECLARED_OUTPUTS_DIR)]} {
        set header_output [file join $::env(TEST_UNDECLARED_OUTPUTS_DIR) syntaxdb.tcl]
    } else {
        puts stderr "Error: --header-output is required when TEST_UNDECLARED_OUTPUTS_DIR is unset"
        exit 1
    }
}

# The runner is itself launched by tclsh via its wrapper, so we reuse the
# already-loaded interpreter (exec-arch under an aspect action, target-arch
# under a test) for the nagelfar subprocess. TCL_LIBRARY is already set by
# the wrapper against that same interpreter's tclcore.
set tclsh_path [info nameofexecutable]

# Header pass: aggregate every target src into one syntaxdb.
file mkdir [file dirname $header_output]
lassign [run_nagelfar $tclsh_path $nagelfar_path [list -header $header_output {*}$srcs]] \
    header_exit header_output_str

if {$streaming} {flush_stream $header_output_str}
if {$header_exit != 0} {
    if {!$streaming} {flush_stream $header_output_str}
    puts stderr "Error: nagelfar -header failed"
    exit 1
}

# Check pass.
set check_args [list -exitcode -H]
foreach db $syntaxdbs {lappend check_args -s $db}
lappend check_args {*}$extra_args {*}$dep_srcs {*}$srcs

lassign [run_nagelfar $tclsh_path $nagelfar_path $check_args] \
    check_exit check_output_str

if {$streaming} {flush_stream $check_output_str}

# Filter check-pass output to findings on target `--src` files (not
# `--dep-src` ones). Dep findings are informational; the target is what
# this action owns.
set srcs_set [dict create]
foreach src $srcs {
    dict set srcs_set $src 1
}

set target_findings {}
set current_file_is_target 0
foreach line [split $check_output_str "\n"] {
    if {[string match "Checking file *" $line]} {
        set current_file [string range $line 14 end]
        set current_file_is_target [dict exists $srcs_set $current_file]
    } elseif {$current_file_is_target && $line ne ""} {
        lappend target_findings $line
    }
}

if {[llength $target_findings] > 0} {
    if {!$streaming} {
        # Build action failing: dump the full log so users see everything
        # nagelfar produced across both passes. The findings are in it.
        flush_stream $header_output_str
        flush_stream $check_output_str
    }
    # Streaming mode has already surfaced every line live; nothing to
    # re-print. Fail so the aspect/test result matches nagelfar's verdict.
    exit 1
}
