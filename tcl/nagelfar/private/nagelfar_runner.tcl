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
    set nagelfar_path ""
    set syntaxdbs {}
    set extra_args {}
    set header_output ""
    set skip_check 0

    set argv [split_equals $argv]
    set n [llength $argv]
    set i 0
    while {$i < $n} {
        set arg [lindex $argv $i]
        set next [expr {$i + 1 < $n ? [lindex $argv [expr {$i + 1}]] : ""}]
        switch -- $arg {
            "--src" {lappend srcs [rloc $next $use_runfiles $r]; incr i}
            "--nagelfar" {set nagelfar_path [rloc $next $use_runfiles $r]; incr i}
            "--syntaxdb" {lappend syntaxdbs [rloc $next $use_runfiles $r]; incr i}
            "--nagelfar-arg" {lappend extra_args $next; incr i}
            "--header-output" {set header_output $next; incr i}
            "--skip-check" {set skip_check 1}
        }
        incr i
    }

    return [list $srcs $nagelfar_path $syntaxdbs $extra_args $header_output $skip_check]
}

# Run `nagelfar` under the ambient tclsh, returning
# [list exit_code merged_stdout_and_stderr].
proc run_nagelfar {tclsh nagelfar_path cmd_args} {
    set cmd [list $tclsh $nagelfar_path {*}$cmd_args]
    set exit_code [catch {exec {*}$cmd 2>@1} output]
    return [list $exit_code $output]
}

# Flush a captured pass to stderr, appending a trailing newline if the
# output didn't already end with one. No-op when `str` is empty. `label`
# is printed as a banner above the output so consumers can tell the two
# nagelfar passes apart instead of reading duplicate "Checking file"
# lines as a bug.
proc flush_stream {label str} {
    if {$str eq ""} {return}
    puts stderr "===== nagelfar $label ====="
    puts -nonewline stderr $str
    if {[string index $str end] ne "\n"} {puts stderr ""}
}

# nagelfar prints "Could not find file 'X'" and keeps going with exit 0
# when an input file is absent. Guard against that ourselves: every src
# the runner was told about must exist on disk before we hand it to
# nagelfar. Returns the list of missing paths (empty when all good).
proc missing_paths {paths} {
    set missing {}
    foreach p $paths {
        if {![file exists $p]} {
            lappend missing $p
        }
    }
    return $missing
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
    srcs nagelfar_path syntaxdbs extra_args header_output skip_check

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

# nagelfar treats missing files as warnings (stdout, exit 0), so verify
# every input exists up front instead of trusting the exit code below.
set missing [missing_paths $srcs]
if {[llength $missing] > 0} {
    puts stderr "Error: nagelfar inputs missing:"
    foreach p $missing {puts stderr "  $p"}
    exit 1
}

# Header pass: aggregate every target src into one syntaxdb.
file mkdir [file dirname $header_output]
lassign [run_nagelfar $tclsh_path $nagelfar_path [list -header $header_output {*}$srcs]] \
    header_exit header_output_str

if {$streaming} {flush_stream "-header" $header_output_str}
if {$header_exit != 0} {
    if {!$streaming} {flush_stream "-header" $header_output_str}
    puts stderr "Error: nagelfar -header failed"
    exit 1
}

# `--skip-check` targets (e.g. `no_lint`-tagged) still contribute a
# syntaxdb to downstream lint runs — that's the whole reason we did the
# header pass — but we don't want to fail on their own findings.
if {$skip_check} {
    exit 0
}

# Check pass.
set check_args [list -exitcode -H]
foreach db $syntaxdbs {lappend check_args -s $db}
lappend check_args {*}$extra_args {*}$srcs

lassign [run_nagelfar $tclsh_path $nagelfar_path $check_args] \
    check_exit check_output_str

if {$streaming} {flush_stream "-check" $check_output_str}

# Every file passed to nagelfar is a target src, so any non-zero exit is
# a target failure. No line-level filtering needed.
if {$check_exit != 0} {
    if {!$streaming} {
        # Build action failing: dump both passes so users see everything.
        flush_stream "-header" $header_output_str
        flush_stream "-check" $check_output_str
    }
    exit 1
}
