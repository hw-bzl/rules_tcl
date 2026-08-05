namespace eval uses_extern {
    proc greet {} {
        extern::do_thing "hello"
    }
}
