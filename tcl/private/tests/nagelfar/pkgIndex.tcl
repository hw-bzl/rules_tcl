if {![package vsatisfies [package provide Tcl] 8.5-]} {return}
package ifneeded testlib 1.0 [list source [file join $dir test_lib.tcl]]
