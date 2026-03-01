# Nagelfar runner for rules_tcl.
#
# Supports two modes:
#   1. Direct invocation (aspect): args passed on argv
#   2. Args-file mode (test): RULES_TCL_NAGELFAR_ARGS_FILE or
#      RULES_TCL_LINT_ARGS_FILE env var points to an rlocationpath
#      whose contents are the args (one per line).

package require runfiles

proc find_tcllib_module_files {tcllib_modules_dir pkg} {
    set pkg_dir [file join $tcllib_modules_dir $pkg]
    if {[file isdirectory $pkg_dir]} {
        set files {}
        foreach f [glob -nocomplain -directory $pkg_dir *.tcl] {
            if {[file tail $f] ne "pkgIndex.tcl"} {
                lappend files $f
            }
        }
        return $files
    }

    foreach idx [glob -nocomplain \
        -directory $tcllib_modules_dir */pkgIndex.tcl] {
        set fh [open $idx r]
        set idx_content [read $fh]
        close $fh
        if {[string match "*ifneeded $pkg *" $idx_content]} {
            set mod_dir [file dirname $idx]
            set files {}
            foreach f [glob -nocomplain \
                -directory $mod_dir *.tcl] {
                if {[file tail $f] ne "pkgIndex.tcl"} {
                    lappend files $f
                }
            }
            return $files
        }
    }
    return {}
}

proc extract_commands_from_files {files} {
    set commands {}
    foreach f $files {
        set fh [open $f r]
        set content [read $fh]
        close $fh

        set ns ""
        foreach line [split $content "\n"] {
            if {
                [regexp {namespace\s+eval\s+(::?\S+)} \
                    $line -> ns_name]
            } {
                set ns $ns_name
            }
            if {
                [regexp {^\s*proc\s+(::[\w:]+)} \
                    $line -> proc_name]
            } {
                if {$proc_name ni $commands} {
                    lappend commands $proc_name
                }
            }
            if {
                [regexp \
                    {interp\s+alias\s+\{\}\s+(::[\w:]+)} \
                    $line -> alias_name]
            } {
                if {$alias_name ni $commands} {
                    lappend commands $alias_name
                }
            }
            if {
                $ns ne "" && [regexp \
                    {namespace\s+export\s+(.*)} $line -> exports]
            } {
                set exports [string map {\\ ""} $exports]
                foreach cmd $exports {
                    set cmd [string trim $cmd]
                    if {$cmd eq ""} {continue}
                    set fqn "${ns}::${cmd}"
                    if {$fqn ni $commands} {
                        lappend commands $fqn
                    }
                }
            }
        }
    }
    return $commands
}

proc generate_tcllib_syntaxdb {srcs tcllib_modules_dir} {
    set required_pkgs {}
    foreach src $srcs {
        set fh [open $src r]
        set content [read $fh]
        close $fh
        foreach line [split $content "\n"] {
            if {
                [regexp \
                    {^\s*package\s+require\s+(\S+)} \
                    $line -> pkg]
            } {
                if {$pkg ne "Tcl" && $pkg ni $required_pkgs} {
                    lappend required_pkgs $pkg
                }
            }
        }
    }

    if {[llength $required_pkgs] == 0} {
        return {}
    }

    set all_commands {}
    foreach pkg $required_pkgs {
        set files [find_tcllib_module_files \
            $tcllib_modules_dir $pkg]
        foreach cmd [extract_commands_from_files $files] {
            if {$cmd ni $all_commands} {
                lappend all_commands $cmd
            }
        }
    }

    if {[llength $all_commands] == 0} {
        return {}
    }

    set db_lines {}
    lappend db_lines \
        "# Auto-generated tcllib syntax database"
    foreach cmd $all_commands {
        set cmd [regsub {^::} $cmd ""]
        lappend db_lines \
            "lappend ::knownCommands [list $cmd]"
        lappend db_lines \
            "set ::syntax([list $cmd]) {x*}"
    }
    return $db_lines
}

proc parse_args {argv use_runfiles r} {
    set srcs {}
    set dep_srcs {}
    set tclsh_path ""
    set tcl_library_path ""
    set nagelfar_path ""
    set syntaxdbs {}
    set marker ""
    set tcllib_pkg_index ""

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
        } elseif {[string match "--tclsh=*" $arg]} {
            set tclsh_path [string range $arg 8 end]
            if {$use_runfiles} {
                set tclsh_path [runfiles::rlocation $r $tclsh_path]
            }
        } elseif {$arg eq "--tclsh" && $i + 1 < [llength $argv]} {
            incr i
            set tclsh_path [lindex $argv $i]
            if {$use_runfiles} {
                set tclsh_path [runfiles::rlocation $r $tclsh_path]
            }
        } elseif {[string match "--tcl-library=*" $arg]} {
            set tcl_library_path [string range $arg 14 end]
            if {$use_runfiles} {
                set tcl_library_path [runfiles::rlocation $r $tcl_library_path]
            }
        } elseif {$arg eq "--tcl-library" && $i + 1 < [llength $argv]} {
            incr i
            set tcl_library_path [lindex $argv $i]
            if {$use_runfiles} {
                set tcl_library_path [runfiles::rlocation $r $tcl_library_path]
            }
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
        } elseif {[string match "--marker=*" $arg]} {
            set marker [string range $arg 9 end]
        } elseif {$arg eq "--marker" && $i + 1 < [llength $argv]} {
            incr i
            set marker [lindex $argv $i]
        } elseif {[string match "--tcllib-pkg-index=*" $arg]} {
            set tcllib_pkg_index [string range $arg 19 end]
            if {$use_runfiles} {
                set tcllib_pkg_index [runfiles::rlocation $r $tcllib_pkg_index]
            }
        } elseif {$arg eq "--tcllib-pkg-index" && $i + 1 < [llength $argv]} {
            incr i
            set tcllib_pkg_index [lindex $argv $i]
            if {$use_runfiles} {
                set tcllib_pkg_index [runfiles::rlocation $r $tcllib_pkg_index]
            }
        }

        incr i
    }

    return [list $srcs $dep_srcs $tclsh_path $tcl_library_path \
        $nagelfar_path $syntaxdbs $marker $tcllib_pkg_index]
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
    srcs dep_srcs tclsh_path tcl_library_path \
    nagelfar_path syntaxdbs marker tcllib_pkg_index

if {$tclsh_path eq ""} {
    puts stderr "Error: --tclsh is required"
    exit 1
}
if {$nagelfar_path eq ""} {
    puts stderr "Error: --nagelfar is required"
    exit 1
}
if {[llength $srcs] == 0} {
    puts stderr "Error: at least one --src is required"
    exit 1
}

if {$tcl_library_path ne ""} {
    set ::env(TCL_LIBRARY) [file dirname $tcl_library_path]
}

if {$tcllib_pkg_index ne ""} {
    set tcllib_modules_dir [file dirname $tcllib_pkg_index]
    set all_check_srcs [concat $dep_srcs $srcs]
    set db_lines [generate_tcllib_syntaxdb \
        $all_check_srcs $tcllib_modules_dir]
    if {[llength $db_lines] > 0} {
        set db_fh [file tempfile db_path .syntaxdb.tcl]
        puts $db_fh [join $db_lines "\n"]
        close $db_fh
        lappend syntaxdbs $db_path
    }
}

set cmd [list $tclsh_path $nagelfar_path -exitcode -H]
foreach db $syntaxdbs {
    lappend cmd -s $db
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
