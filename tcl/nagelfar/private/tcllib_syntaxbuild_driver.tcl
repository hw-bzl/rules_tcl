# Driver `tcl_binary` that force-loads every tcllib package registered in
# the interpreter's auto_path and then hands off to nagelfar's
# `syntaxbuild.tcl`, which snapshots the interpreter's known commands into
# the output file and exits.
#
# tcllib is on `auto_path` via the standard `tcl_binary` wrapper's toolchain
# resolution — no need to source a pkgIndex here.
#
# Invoked as:
#     syntaxbuild_driver <output> <syntaxbuild>

if {[llength $argv] != 2} {
    puts stderr "Usage: $argv0 <output> <syntaxbuild>"
    exit 1
}

lassign $argv output syntaxbuild

# Trigger tcllib's top-level pkgIndex.tcl so its `package ifneeded` chain
# registers every sub-package. Without this, `[package names]` below only
# sees the core packages tclsh ships with — auto_path is populated but
# unscanned until the first `package require`.
package require tcllib

# Force-load every registered package so its commands populate
# `[info commands]` before syntaxbuild snapshots.
foreach pkg [package names] {
    if {$pkg eq "Tcl" || $pkg eq "Tk"} {continue}
    catch {package require $pkg}
}

# Buffer syntaxbuild's stdout/stderr and only surface it on non-zero exit.
# syntaxbuild.tcl emits informational lines ("Skipping syntax(case) since
# case is not known.", etc.) for every entry whose command isn't loaded in
# this interp — legitimate for a stock tcllib snapshot, but pure noise in
# a green build log. The exit code is the authoritative success signal.
set ::rules_tcl_buffered {}
rename ::puts ::rules_tcl_real_puts
proc ::puts {args} {
    set nonewline 0
    if {[lindex $args 0] eq "-nonewline"} {
        set nonewline 1
        set args [lrange $args 1 end]
    }
    # Normalize to (channel, data). `puts $data` implicitly targets stdout.
    if {[llength $args] == 1} {
        set channel stdout
        set data [lindex $args 0]
    } elseif {[llength $args] == 2} {
        lassign $args channel data
    } else {
        # Malformed — let the real puts raise its usage error.
        ::rules_tcl_real_puts {*}$args
        return
    }
    if {$channel eq "stdout" || $channel eq "stderr"} {
        append ::rules_tcl_buffered $data
        if {!$nonewline} {append ::rules_tcl_buffered "\n"}
    } elseif {$nonewline} {
        ::rules_tcl_real_puts -nonewline $channel $data
    } else {
        ::rules_tcl_real_puts $channel $data
    }
}

rename ::exit ::rules_tcl_real_exit
proc ::exit {{code 0}} {
    if {$code != 0 && $::rules_tcl_buffered ne ""} {
        ::rules_tcl_real_puts stderr $::rules_tcl_buffered
    }
    ::rules_tcl_real_exit $code
}

# Hand off to syntaxbuild.tcl. Its auto-exec block reads argv[0] as the
# output filename and calls `exit` when done.
set argv [list $output]
set argc 1
if {[catch {source $syntaxbuild} err]} {
    ::rules_tcl_real_puts stderr $::rules_tcl_buffered
    ::rules_tcl_real_puts stderr "Error sourcing syntaxbuild: $err"
    ::rules_tcl_real_exit 1
}
