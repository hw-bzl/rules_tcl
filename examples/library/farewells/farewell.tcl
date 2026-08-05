# The farewells library, consumed via `source` rather than `package require`.

namespace eval farewells {
    proc farewell {name} {
        puts "Goodbye $name"
    }
}
