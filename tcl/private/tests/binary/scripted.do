set output ""
for {set i 0} {$i < $argc} {incr i} {
    set arg [lindex $argv $i]
    if {$arg eq "--output"} {
        incr i
        set output [lindex $argv $i]
    }
}

if {$output eq ""} {
    puts stderr "Usage: $argv0 --output <file path>"
    exit 1
}

file mkdir [file dirname $output]

set fh [open $output "w"]
puts $fh "Do-Re-Mi-Fa-Sol."
close $fh
