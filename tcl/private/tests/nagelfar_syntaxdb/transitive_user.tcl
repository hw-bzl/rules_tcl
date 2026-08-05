namespace eval transitive_user {
    proc greet {} {
        extern::do_thing "world"
    }
}
