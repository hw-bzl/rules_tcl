# Ensure `MODULE.bazel` versions match `version.bzl`

package require runfiles

# Create runfiles handle
set r [runfiles::create]

# Resolve the path to MODULE.bazel
set module_path [runfiles::rlocation $r "$::env(MODULE_BAZEL)"]

if {![file exists $module_path]} {
    puts stderr "Error: MODULE.bazel not found at '$module_path'"
    exit 1
}

# Read the contents of MODULE.bazel
set fh [open $module_path "r"]
set content [read $fh]
close $fh

# Extract version string using a regular expression
set version_match [regexp -line -nocase {version\s*=\s*"([^"]+)"} $content _ found_version]

if {!$version_match} {
    puts stderr "Error: Could not find version in MODULE.bazel"
    exit 1
}

# Compare with environment variable VERSION
if {![info exists ::env(VERSION)]} {
    puts stderr "Error: VERSION environment variable not set"
    exit 1
}

set expected_version $::env(VERSION)

if {$found_version eq $expected_version} {
    puts "PASS: MODULE.bazel version '$found_version' matches VERSION='$expected_version'"
    exit 0
} else {
    set msg "FAIL: MODULE.bazel version '$found_version'"
    puts stderr "$msg does not match VERSION='$expected_version'"
    exit 1
}
