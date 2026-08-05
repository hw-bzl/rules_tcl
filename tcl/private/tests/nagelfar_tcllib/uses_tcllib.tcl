package require struct::list

namespace eval uses_tcllib {
    proc reversed {items} {
        return [struct::list reverse $items]
    }
}
