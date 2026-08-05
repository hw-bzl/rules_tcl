# Nagelfar runner for rules_tcl.
#
# Supports two modes:
#   1. Direct invocation (aspect): args passed on argv
#   2. Args-file mode (test): RULES_TCL_NAGELFAR_ARGS_FILE or
#      RULES_TCL_LINT_ARGS_FILE env var points to an rlocationpath
#      whose contents are the args (one per line).

package require runfiles

proc parse_args {argv use_runfiles r} {
    set srcs {}
    set dep_srcs {}
    set nagelfar_path ""
    set syntaxdbs {}
    set extra_args {}
    set marker ""

    set i 0
    while {$i < [llength $argv]} {
        set arg [lindex $argv $i]

        if {[string match "--src=*" $arg]} {
            set val [string range $arg 6 end]
            if {$use_runfiles} {
                set val [runfiles::rlocation $r $val]
            }
            lappend srcs $val
        } elseif {$arg eq "--src" && $i + 1 < [llength $argv]} {
            incr i
            set val [lindex $argv $i]
            if {$use_runfiles} {
                set val [runfiles::rlocation $r $val]
            }
            lappend srcs $val
        } elseif {[string match "--dep-src=*" $arg]} {
            set val [string range $arg 10 end]
            if {$use_runfiles} {
                set val [runfiles::rlocation $r $val]
            }
            lappend dep_srcs $val
        } elseif {$arg eq "--dep-src" && $i + 1 < [llength $argv]} {
            incr i
            set val [lindex $argv $i]
            if {$use_runfiles} {
                set val [runfiles::rlocation $r $val]
            }
            lappend dep_srcs $val
        } elseif {[string match "--nagelfar=*" $arg]} {
            set nagelfar_path [string range $arg 11 end]
            if {$use_runfiles} {
                set nagelfar_path [runfiles::rlocation $r $nagelfar_path]
            }
        } elseif {$arg eq "--nagelfar" && $i + 1 < [llength $argv]} {
            incr i
            set nagelfar_path [lindex $argv $i]
            if {$use_runfiles} {
                set nagelfar_path [runfiles::rlocation $r $nagelfar_path]
            }
        } elseif {[string match "--syntaxdb=*" $arg]} {
            set val [string range $arg 11 end]
            if {$use_runfiles} {
                set val [runfiles::rlocation $r $val]
            }
            lappend syntaxdbs $val
        } elseif {$arg eq "--syntaxdb" && $i + 1 < [llength $argv]} {
            incr i
            set val [lindex $argv $i]
            if {$use_runfiles} {
                set val [runfiles::rlocation $r $val]
            }
            lappend syntaxdbs $val
        } elseif {[string match "--nagelfar-arg=*" $arg]} {
            lappend extra_args [string range $arg 15 end]
        } elseif {$arg eq "--nagelfar-arg" && $i + 1 < [llength $argv]} {
            incr i
            lappend extra_args [lindex $argv $i]
        } elseif {[string match "--marker=*" $arg]} {
            set marker [string range $arg 9 end]
        } elseif {$arg eq "--marker" && $i + 1 < [llength $argv]} {
            incr i
            set marker [lindex $argv $i]
        }

        incr i
    }

    return [list $srcs $dep_srcs \
        $nagelfar_path $syntaxdbs $extra_args $marker]
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

set parsed [parse_args $effective_argv $use_runfiles $r]
lassign $parsed \
    srcs dep_srcs \
    nagelfar_path syntaxdbs extra_args marker

if {$nagelfar_path eq ""} {
    puts stderr "Error: --nagelfar is required"
    exit 1
}
if {[llength $srcs] == 0} {
    puts stderr "Error: at least one --src is required"
    exit 1
}

# The runner is itself launched by tclsh via its wrapper, so we reuse the
# already-loaded interpreter (exec-arch under an aspect action, target-arch
# under a test) for the nagelfar subprocess. TCL_LIBRARY is already set by
# the wrapper against that same interpreter's tclcore.
set tclsh_path [info nameofexecutable]

set cmd [list $tclsh_path $nagelfar_path -exitcode -H]
foreach db $syntaxdbs {
    lappend cmd -s $db
}
foreach extra $extra_args {
    lappend cmd $extra
}
foreach dep $dep_srcs {
    lappend cmd $dep
}
foreach src $srcs {
    lappend cmd $src
}

set exit_code [catch {exec {*}$cmd 2>@1} output]

if {$exit_code != 0} {
    set srcs_set [dict create]
    foreach src $srcs {
        dict set srcs_set $src 1
    }

    set target_findings {}
    set current_file_is_target 0

    foreach line [split $output "\n"] {
        if {[string match "Checking file *" $line]} {
            set current_file [string range $line 14 end]
            set current_file_is_target [dict exists $srcs_set $current_file]
        } elseif {$current_file_is_target && $line ne ""} {
            lappend target_findings $line
        }
    }

    if {[llength $target_findings] > 0} {
        foreach finding $target_findings {
            puts stderr $finding
        }
        exit 1
    }
}

if {$marker ne ""} {
    file mkdir [file dirname $marker]
    set fh [open $marker w]
    close $fh
}
