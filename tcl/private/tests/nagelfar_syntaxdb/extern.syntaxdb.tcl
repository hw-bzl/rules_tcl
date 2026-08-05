# Test syntax database declaring a made-up "extern" package so nagelfar
# recognises calls to `extern::do_thing` from Tcl code that has no source
# dependency on the package.

lappend ::knownCommands extern::do_thing
set ::syntax(extern::do_thing) {x*}
