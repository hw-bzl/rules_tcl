# rules_tcl entrypoint.

# Configure TCLLIBPATH
lappend auto_path $::env(TCLLIB_LIBRARY)

package require json
package require fileutil

# Validate arguments
if {$argc < 3} {
    puts stderr "Usage: $argv0 <config.json> <main.tcl> -- \[args...\]"
    exit 1
}

# Extract config and main script paths
set config_path [lindex $argv 0]
set main_path [lindex $argv 1]

# Find `--` separator
set separator_index -1
for {set i 2} {$i < $argc} {incr i} {
    if {[lindex $argv $i] eq "--"} {
        set separator_index $i
        break
    }
}
if {$separator_index == -1} {
    puts stderr "Missing -- separator after config and main script paths"
    exit 1
}

# Extract extra args and trim $argv
set extra_args [lrange $argv [expr {$separator_index + 1}] end]
set argv [lrange $argv 0 [expr {$separator_index - 1}]]

# Load JSON config
set config_fh [open $config_path]
set json_text [read $config_fh]
close $config_fh
set config [::json::json2dict $json_text]
set includes [dict get $config includes]
if {$includes eq ""} {
    set includes {}
}

# Determine RUNFILES_DIR
if {[info exists ::env(RUNFILES_DIR)]} {
    set runfiles $::env(RUNFILES_DIR)
} elseif {[info exists ::env(RUNFILES_MANIFEST_FILE)]} {
    set manifest $::env(RUNFILES_MANIFEST_FILE)
    set runfiles [fileutil::tempdir]
    if {[info exists ::env(RULES_TCL_DEBUG)]} {
        puts stderr "\[DEBUG\] RUNFILES_DIR created: $runfiles"
    }
    set ::env(RUNFILES_DIR) $runfiles

    # Copy files from manifest
    set mfh [open $manifest]
    while {[gets $mfh line] >= 0} {
        if {[string trim $line] eq ""} {
            continue
        }
        set parts [split $line " "]
        if {[llength $parts] < 2} {
            continue
        }
        lassign $parts rel_path real_path
        set dst_path [file join $runfiles $rel_path]
        file mkdir [file dirname $dst_path]
        file copy -force $real_path $dst_path
    }
    close $mfh
} else {
    puts stderr "RUNFILES_DIR is not set and RUNFILES_MANIFEST_FILE is not provided."
    exit 1
}

# Make RUNFILES_DIR absolute
if {[file pathtype $runfiles] ne "absolute"} {
    set runfiles [file normalize $runfiles]
    set ::env(RUNFILES_DIR) $runfiles
}

# Build include paths
set include_paths {}
foreach inc $includes {
    lappend include_paths [file join $runfiles $inc]
}

set tclsh_path [info nameofexecutable]

# Build full command
set cmd [concat $tclsh_path $main_path $extra_args]

if {[info exists ::env(RULES_TCL_DEBUG)]} {
    puts stderr "\[DEBUG\] Subprocess command: $cmd"
}

# Set TCLLIBPATH env var
set ::env(TCLLIBPATH) [join $include_paths " "]

# Execute
set exit_code [catch {
    exec {*}$cmd >@stdout 2>@stderr
}]

if {$exit_code != 0} {
    exit $exit_code
}
