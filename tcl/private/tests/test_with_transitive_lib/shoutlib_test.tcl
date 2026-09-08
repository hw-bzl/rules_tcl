# Regression: `shoutlib` is the only declared dep, but loading it runs
# `package require writelib`. That resolves only if a dep's own deps also
# contribute their `pkgIndex.tcl` directory to `auto_path`.

package require shoutlib

# Environment setup
set tmpdir $::env(TEST_TMPDIR)
if {$tmpdir eq ""} {
    puts stderr "TEST_TMPDIR is not set"
    exit 1
}
set outfile [file join $tmpdir output.txt]

shoutlib::write_shout $outfile "La-Li-Lu-Le-Lo"

# Read back the file
set fh [open $outfile "r"]
set actual [string trimright [read $fh]]
close $fh

set expected "LA-LI-LU-LE-LO"
if {$actual ne $expected} {
    puts stderr "ERROR: File contents mismatch!\nExpected: $expected\nActual:   $actual"
    exit 1
}

puts "SUCCESS: Test passed. File contents match."
