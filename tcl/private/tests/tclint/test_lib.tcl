# A test library for tclint checks.

namespace eval testlib {
    proc hello {name} {
        return "Hello, $name!"
    }

    proc add {a b} {
        return [expr {$a + $b}]
    }

    package provide testlib 1.0
}
