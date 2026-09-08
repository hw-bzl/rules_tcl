# A library that reaches its own dependency through `package require`, so a
# consumer depending only on `shoutlib` still needs `writelib` on `auto_path`.
package require writelib

namespace eval shoutlib {
    proc write_shout {filename content} {
        writelib::write_output $filename [string toupper $content]
    }

    package provide shoutlib 1.0
}
