# Unit tests for the parts of `runfiles` that don't need a real Bazel
# runfiles tree — manifest parsing, repo-mapping parsing, and the
# `rlocation` / `rlocation_from` behavior against synthetic inputs.

package require runfiles

set ::failures 0

proc assert_equal {label actual expected} {
    if {$actual ne $expected} {
        puts stderr "FAIL \[$label\]"
        puts stderr "  expected: $expected"
        puts stderr "  actual:   $actual"
        incr ::failures
        return 0
    }
    puts "ok    \[$label\]"
    return 1
}

proc assert_error {label script} {
    if {[catch {uplevel 1 $script}]} {
        puts "ok    \[$label\] (raised)"
        return 1
    }
    puts stderr "FAIL \[$label\] expected error, got none"
    incr ::failures
    return 0
}

set tmp $::env(TEST_TMPDIR)

# --- manifest parsing ---------------------------------------------------

set manifest_content [join {
    "a/b c/d"
    " a\\sb/c\\nd\\be f g/h\\ni\\bj"
    "empty-file "
} "\n"]
set manifest_path [file join $tmp manifest_parsing.txt]
set fh [open $manifest_path w]
puts -nonewline $fh $manifest_content
close $fh

set r [runfiles::new_manifest_based $manifest_path]

assert_equal "manifest simple key" \
    [runfiles::rlocation $r "a/b"] "c/d"
# Escaped-key line: \s in key → space, \n in value → newline, \b → backslash.
assert_equal "manifest escaped key" \
    [runfiles::rlocation $r "a b/c\nd\\e"] "f g/h\ni\\j"
assert_equal "manifest empty-value entry" \
    [runfiles::rlocation $r "empty-file"] ""
assert_equal "manifest missing entry" \
    [runfiles::rlocation $r "does/not/exist"] ""

# --- absolute path passthrough -----------------------------------------

assert_equal "absolute path passthrough (manifest mode)" \
    [runfiles::rlocation $r "/tmp/abs/path"] "/tmp/abs/path"
assert_equal "rlocation empty string" \
    [runfiles::rlocation $r ""] ""

# --- directory mode -----------------------------------------------------

set dirmode_root [file join $tmp dirmode_root]
file mkdir $dirmode_root
set d [runfiles::new_directory_based $dirmode_root]
assert_equal "directory join" \
    [runfiles::rlocation $d "workspace/data.txt"] \
    [file join $dirmode_root workspace/data.txt]
assert_equal "directory absolute passthrough" \
    [runfiles::rlocation $d "/etc/hostname"] "/etc/hostname"

# --- repo mapping parsing ----------------------------------------------

set mapping_content [join {
    ",rules_rust,rules_rust"
    "bazel_tools,__main__,rules_rust"
    "+deps+*,aaa,_main"
    "+deps+*,dep,+deps+dep1"
    "+other+exact,foo,bar"
} "\n"]
set mapping [runfiles::_parse_repo_mapping $mapping_content]

assert_equal "repo mapping exact hit" \
    [runfiles::_repo_mapping_get $mapping "bazel_tools" "__main__"] "rules_rust"
assert_equal "repo mapping empty source_repo" \
    [runfiles::_repo_mapping_get $mapping "" "rules_rust"] "rules_rust"
assert_equal "repo mapping prefix hit" \
    [runfiles::_repo_mapping_get $mapping "+deps+dep1" "aaa"] "_main"
assert_equal "repo mapping prefix hit alt apparent" \
    [runfiles::_repo_mapping_get $mapping "+deps+dep3" "dep"] "+deps+dep1"
assert_equal "repo mapping miss" \
    [runfiles::_repo_mapping_get $mapping "unknown" "aaa"] ""

assert_error "repo mapping rejects malformed line" {
    runfiles::_parse_repo_mapping "not,enough"
}

# --- rlocation_from with in-memory mapping -----------------------------

# Point at a synthetic manifest-based handle so the rewrite is
# observable in the return value.
set rf_manifest_path [file join $tmp rlocation_from.txt]
set fh [open $rf_manifest_path w]
puts $fh "canonical/x/y actual/x/y"
puts $fh "+deps+dep1/foo/bar real/foo/bar"
puts $fh "_main/aaa/some/path resolved/main/path"
close $fh
set rf [runfiles::new_manifest_based $rf_manifest_path]
runfiles::_set_repo_mapping $rf [runfiles::_parse_repo_mapping $mapping_content]
# Also register a plain "source_repo,apparent_name,canonical" so we can
# exercise the exact-match rewrite end-to-end.
runfiles::_set_repo_mapping $rf [runfiles::_parse_repo_mapping [join [list \
    $mapping_content \
    "source_repo,apparent_name,canonical"] "\n"]]
# Extend the manifest lookup for the exact-match case:
namespace upvar ::runfiles $rf obj
dict set obj(manifest_dict) "canonical/x/y" "actual/x/y"

assert_equal "rlocation_from exact match rewrites first segment" \
    [runfiles::rlocation_from $rf "apparent_name/x/y" "source_repo"] \
    "actual/x/y"
assert_equal "rlocation_from prefix match rewrites first segment" \
    [runfiles::rlocation_from $rf "dep/foo/bar" "+deps+dep3"] \
    "real/foo/bar"
assert_equal "rlocation_from unmapped falls through unchanged" \
    [runfiles::rlocation_from $rf "canonical/x/y" "no_mapping_source"] \
    "actual/x/y"
assert_equal "rlocation_from absolute passthrough" \
    [runfiles::rlocation_from $rf "/abs/path" "source_repo"] "/abs/path"
assert_equal "rlocation_from empty string" \
    [runfiles::rlocation_from $rf "" "source_repo"] ""

# --- final report -------------------------------------------------------

if {$::failures > 0} {
    puts stderr "FAILED: $::failures assertion(s)"
    exit 1
}
puts "PASSED"
