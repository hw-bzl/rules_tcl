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

# Hand off to syntaxbuild.tcl. Its auto-exec block reads argv[0] as the
# output filename and calls `exit` when done.
set argv [list $output]
set argc 1
source $syntaxbuild
