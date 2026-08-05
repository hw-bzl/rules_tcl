# A tcl script that exercises both consumption styles: `package require`
# for a library with a `pkgIndex.tcl` and `source` (via runfiles) for one
# without.

package require greetings
package require runfiles

set r [runfiles::create]
source [runfiles::rlocation $r $::env(FAREWELL_TCL)]

greetings::greet "World"
farewells::farewell "World"
