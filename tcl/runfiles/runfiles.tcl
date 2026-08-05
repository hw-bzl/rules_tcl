# # Runfiles
#
# Bazel Runfiles Interface for Tcl.
#
# Behavior matches Bazel's language runfiles libraries (bzlmod-aware,
# manifest-aware, `<binary>.runfiles_manifest` fallback). Modeled after
# `rules_rust//rust/runfiles`.
#
# ## Usage
#
# ```starlark
# tcl_binary(
#     name = "foo",
#     srcs = ["foo.tcl"],
#     data = ["data.txt"],
#     env = {
#         "DATA_RLOCATIONPATH": "$(rlocationpath data.txt)",
#     },
#     deps = ["//tcl/runfiles"],
# )
# ```
#
# ```tcl
# package require runfiles
# set r [runfiles::create]
# set abs_path [runfiles::rlocation $r $::env(DATA_RLOCATIONPATH)]
# ```
#
# For bzlmod-aware lookups by apparent repo name, pass the *source* repo
# (the canonical repo name of the code calling `rlocation_from`) so the
# `_repo_mapping` file can rewrite apparent names into canonical ones:
#
# ```tcl
# set path [runfiles::rlocation_from $r "my_dep/some/data.txt" $::env(REPOSITORY_NAME)]
# ```

namespace eval runfiles {
    # Monotonic counter for handle names.
    variable instances 0

    # Handle → per-instance dict. Each entry has keys:
    #   mode           "directory" | "manifest"
    #   runfiles_dir   (directory mode) absolute path
    #   manifest_dict  (manifest mode) dict of rlocationpath → real path
    #   repo_mapping   bzlmod mapping (see `_empty_repo_mapping`)
    variable objects [dict create]

    # Bazel-documented environment variables consulted during discovery.
    variable RUNFILES_DIR_ENV_VAR RUNFILES_DIR
    variable MANIFEST_FILE_ENV_VAR RUNFILES_MANIFEST_FILE
    variable TEST_SRCDIR_ENV_VAR TEST_SRCDIR
}

proc runfiles::create {} {
    # Construct a runfiles object from the process environment.
    #
    # Discovery order mirrors Bazel's language runfiles libraries:
    #   1. `RUNFILES_MANIFEST_FILE` (if set and non-empty)
    #   2. Runfiles directory from `RUNFILES_DIR`, `TEST_SRCDIR`, or an
    #      `argv[0]`-based walk. If the resolved directory contains a
    #      `MANIFEST` file, that manifest is preferred.
    #   3. `<argv[0]>.runfiles_manifest` sibling file (written by every
    #      Bazel binary action even without `bazel run`).
    #
    # After the mode is chosen, `_repo_mapping` is read from the tree
    # (if present) for bzlmod-aware `rlocation_from` lookups.
    #
    # Returns:
    #   An object handle for use with `rlocation` and `rlocation_from`.

    variable MANIFEST_FILE_ENV_VAR

    set manifest_env ""
    if {
        [info exists ::env($MANIFEST_FILE_ENV_VAR)]
        && $::env($MANIFEST_FILE_ENV_VAR) ne ""
    } {
        set manifest_env $::env($MANIFEST_FILE_ENV_VAR)
    }

    if {$manifest_env ne ""} {
        set handle [runfiles::new_manifest_based $manifest_env]
    } else {
        set dir [runfiles::find_runfiles_dir]
        if {$dir ne ""} {
            set inner_manifest [file join $dir MANIFEST]
            if {[file exists $inner_manifest]} {
                set handle [runfiles::new_manifest_based $inner_manifest]
            } else {
                set handle [runfiles::new_directory_based $dir]
            }
        } else {
            set sibling [runfiles::find_runfiles_manifest_from_argv0]
            if {$sibling ne ""} {
                set handle [runfiles::new_manifest_based $sibling]
            } else {
                error "Unable to locate runfiles."
            }
        }
    }

    # Best-effort: load `_repo_mapping` from the resolved tree. An absent
    # file is fine — the mapping stays empty.
    set mapping_path [runfiles::_raw_rlocation $handle _repo_mapping]
    if {$mapping_path ne "" && [file exists $mapping_path]} {
        set fh [open $mapping_path r]
        set content [read $fh]
        close $fh
        runfiles::_set_repo_mapping $handle [runfiles::_parse_repo_mapping $content]
    }

    return $handle
}

proc runfiles::new_directory_based {dir} {
    # Construct a directory-based runfiles handle rooted at `dir`.

    if {![file isdirectory $dir]} {
        error "Invalid runfiles directory: $dir"
    }

    set handle [runfiles::_new_handle]
    runfiles::_store $handle [dict create \
        mode directory \
        runfiles_dir $dir \
        repo_mapping [runfiles::_empty_repo_mapping]]
    return $handle
}

proc runfiles::new_manifest_based {manifest_path} {
    # Construct a manifest-based runfiles handle by parsing `manifest_path`.

    if {![file exists $manifest_path]} {
        error "Runfiles manifest file does not exist: $manifest_path"
    }

    set fh [open $manifest_path r]
    set content [read $fh]
    close $fh

    set handle [runfiles::_new_handle]
    runfiles::_store $handle [dict create \
        mode manifest \
        manifest_dict [runfiles::_parse_manifest $content] \
        repo_mapping [runfiles::_empty_repo_mapping]]
    return $handle
}

proc runfiles::rlocation {handle path} {
    # Return the runtime path of a runfile. Absolute paths pass through.
    #
    # This entrypoint is not bzlmod-aware. Prefer `rlocation_from` for
    # paths whose first segment is an apparent (non-canonical) repo name.
    #
    # Returns:
    #   The resolved absolute path, or empty string if `path` is empty
    #   or (for manifest-based lookups) not present in the manifest.

    if {[string length $path] == 0} {
        return ""
    }
    if {[file pathtype $path] eq "absolute"} {
        return $path
    }
    return [runfiles::_raw_rlocation $handle $path]
}

proc runfiles::rlocation_from {handle path source_repo} {
    # bzlmod-aware runfile lookup. `source_repo` is the canonical repo
    # of the code performing the lookup; the first segment of `path` is
    # treated as an apparent repo name and rewritten via `_repo_mapping`.
    #
    # When no mapping applies, `path` is used as-is (matching the
    # reference Rust implementation).

    if {[string length $path] == 0} {
        return ""
    }
    if {[file pathtype $path] eq "absolute"} {
        return $path
    }

    set slash [string first "/" $path]
    if {$slash < 0} {
        set repo_alias $path
        set repo_path ""
    } else {
        set repo_alias [string range $path 0 [expr {$slash - 1}]]
        set repo_path [string range $path [expr {$slash + 1}] end]
    }

    set mapping [runfiles::_field $handle repo_mapping]
    set target [runfiles::_repo_mapping_get $mapping $source_repo $repo_alias]
    if {$target eq ""} {
        return [runfiles::_raw_rlocation $handle $path]
    }
    if {$repo_path eq ""} {
        return [runfiles::_raw_rlocation $handle $target]
    }
    return [runfiles::_raw_rlocation $handle "$target/$repo_path"]
}

proc runfiles::find_runfiles_dir {} {
    # Locate a runfiles directory via env vars, then argv[0].
    # Returns empty string on failure so callers can fall through.

    variable RUNFILES_DIR_ENV_VAR
    variable TEST_SRCDIR_ENV_VAR

    if {[info exists ::env($RUNFILES_DIR_ENV_VAR)]} {
        set d $::env($RUNFILES_DIR_ENV_VAR)
        if {[file isdirectory $d]} {
            return $d
        }
    }
    if {[info exists ::env($TEST_SRCDIR_ENV_VAR)]} {
        set d $::env($TEST_SRCDIR_ENV_VAR)
        if {[file isdirectory $d]} {
            return $d
        }
    }
    return [runfiles::_find_runfiles_dir_from_argv0]
}

proc runfiles::find_runfiles_manifest_from_argv0 {} {
    # Return a `<binary>.runfiles_manifest` sibling of argv[0] (or the
    # interpreter as a fallback), else empty string.

    set candidates [runfiles::_argv0_candidates]
    foreach c $candidates {
        set m [runfiles::_manifest_for $c]
        if {$m ne ""} {
            return $m
        }
    }
    return ""
}

# --- internal helpers ---------------------------------------------------

proc runfiles::_new_handle {} {
    variable instances
    incr instances
    return "runfiles_obj_$instances"
}

proc runfiles::_store {handle instance_dict} {
    variable objects
    dict set objects $handle $instance_dict
}

proc runfiles::_field {handle key} {
    variable objects
    return [dict get $objects $handle $key]
}

proc runfiles::_has_field {handle key} {
    variable objects
    return [dict exists $objects $handle $key]
}

proc runfiles::_set_repo_mapping {handle mapping} {
    variable objects
    dict set objects $handle repo_mapping $mapping
}

proc runfiles::_raw_rlocation {handle path} {
    set mode [runfiles::_field $handle mode]
    if {$mode eq "directory"} {
        return [file join [runfiles::_field $handle runfiles_dir] $path]
    }
    if {$mode eq "manifest"} {
        set map [runfiles::_field $handle manifest_dict]
        if {[dict exists $map $path]} {
            return [dict get $map $path]
        }
        return ""
    }
    error "Invalid runfiles handle: unknown mode"
}

proc runfiles::_empty_repo_mapping {} {
    return [dict create exact [dict create] prefixes [list]]
}

proc runfiles::_parse_manifest {content} {
    # Parse a Bazel `SourceManifestAction` manifest into a dict.
    #
    # Lines starting with a space use the escaped format:
    #   \s → " ", \n → "\n", \b → "\\".
    # Otherwise, split on the first space with no unescaping.
    # See:
    #   https://github.com/bazelbuild/bazel/blob/3cb75e7bb181e3fb2b33707c172bf80431dc4712/src/main/java/com/google/devtools/build/lib/analysis/SourceManifestAction.java#L77-L84

    set entries [dict create]
    foreach line [split $content "\n"] {
        if {$line eq ""} {
            continue
        }
        if {[string index $line 0] eq " "} {
            set rest [string range $line 1 end]
            set sp [string first " " $rest]
            if {$sp < 0} {
                error "Invalid manifest line: $line"
            }
            set raw_key [string range $rest 0 [expr {$sp - 1}]]
            set raw_val [string range $rest [expr {$sp + 1}] end]
            set entry_key [runfiles::_unescape_key $raw_key]
            set entry_val [runfiles::_unescape_value $raw_val]
        } else {
            set sp [string first " " $line]
            if {$sp < 0} {
                error "Invalid manifest line: $line"
            }
            set entry_key [string range $line 0 [expr {$sp - 1}]]
            set entry_val [string range $line [expr {$sp + 1}] end]
        }
        dict set entries $entry_key $entry_val
    }
    return $entries
}

proc runfiles::_unescape_key {s} {
    # Order matches Bazel's SourceManifestAction: keys unescape \s, \n, \b.
    # Do \b (backslash) last so the substitutions don't re-consume other
    # unescaped sequences.
    set s [string map [list "\\s" " "] $s]
    set s [string map [list "\\n" "\n"] $s]
    set s [string map [list "\\b" "\\"] $s]
    return $s
}

proc runfiles::_unescape_value {s} {
    # Values only unescape \n and \b (spaces in values are allowed literal).
    set s [string map [list "\\n" "\n"] $s]
    set s [string map [list "\\b" "\\"] $s]
    return $s
}

proc runfiles::_parse_repo_mapping {content} {
    # Parse a bzlmod `_repo_mapping` file. Each non-empty line has three
    # comma-separated fields: source_repo, apparent_name, target_repo.
    # A trailing `*` on source_repo marks a prefix-match entry (used by
    # `--incompatible_compact_repo_mapping_manifest`).

    set exact_entries [dict create]
    set prefix_entries [list]
    foreach line [split $content "\n"] {
        if {$line eq ""} {
            continue
        }
        set parts [split $line ","]
        if {[llength $parts] < 3} {
            error "Invalid repo mapping line: $line"
        }
        set source_repo [lindex $parts 0]
        set apparent_name [lindex $parts 1]
        # Preserve any commas in target_repo.
        set target_repo [join [lrange $parts 2 end] ","]

        if {[string index $source_repo end] eq "*"} {
            set prefix [string range $source_repo 0 end-1]
            lappend prefix_entries [list $prefix $apparent_name $target_repo]
        } else {
            dict set exact_entries [list $source_repo $apparent_name] $target_repo
        }
    }
    return [dict create exact $exact_entries prefixes $prefix_entries]
}

proc runfiles::_repo_mapping_get {mapping source_repo apparent_name} {
    # Exact match first (O(1)), then linear prefix scan. Returns the
    # canonical target repo, or empty string if no entry matches.

    set exact_entries [dict get $mapping exact]
    set key [list $source_repo $apparent_name]
    if {[dict exists $exact_entries $key]} {
        return [dict get $exact_entries $key]
    }
    foreach entry [dict get $mapping prefixes] {
        lassign $entry prefix stored_apparent target
        if {
            $stored_apparent eq $apparent_name
            && [string equal -length [string length $prefix] $prefix $source_repo]
        } {
            return $target
        }
    }
    return ""
}

proc runfiles::_argv0_candidates {} {
    # Ordered list of executable paths to walk from when hunting for a
    # runfiles tree: argv[0] first (Bazel materializes runfiles next to
    # the launcher), then the Tcl interpreter as a fallback.
    set candidates [list]
    if {[info exists ::argv0] && $::argv0 ne ""} {
        lappend candidates $::argv0
    }
    set exe [info nameofexecutable]
    if {$exe ne "" && $exe ni $candidates} {
        lappend candidates $exe
    }
    return $candidates
}

proc runfiles::_find_runfiles_dir_from_argv0 {} {
    # Walk symlinks starting from argv[0] (falling back to the Tcl
    # interpreter path) looking for either a neighboring `.runfiles`
    # directory or an ancestor whose basename ends in `.runfiles`.

    foreach start [runfiles::_argv0_candidates] {
        set found [runfiles::_walk_for_runfiles_dir $start]
        if {$found ne ""} {
            return $found
        }
    }
    return ""
}

proc runfiles::_walk_for_runfiles_dir {start} {
    set current $start
    # Bound the symlink walk to avoid loops.
    for {set i 0} {$i < 32} {incr i} {
        set sibling "$current.runfiles"
        if {[file isdirectory $sibling]} {
            return $sibling
        }
        set ancestor [file dirname $current]
        while {$ancestor ne "/" && $ancestor ne "." && $ancestor ne ""} {
            if {
                [string match "*.runfiles" [file tail $ancestor]]
                && [file isdirectory $ancestor]
            } {
                return $ancestor
            }
            set parent [file dirname $ancestor]
            if {$parent eq $ancestor} {
                break
            }
            set ancestor $parent
        }
        # Follow one symlink level if possible; otherwise stop.
        if {[catch {file type $current} type] || $type ne "link"} {
            return ""
        }
        set link [file readlink $current]
        if {[file pathtype $link] eq "absolute"} {
            set current $link
        } else {
            set current [file join [file dirname $current] $link]
        }
    }
    return ""
}

proc runfiles::_manifest_for {exe_path} {
    set dir [file dirname $exe_path]
    if {$dir eq "" || $dir eq "."} {
        # Bare basename (PATH lookup): no dir to look next to.
        return ""
    }
    set manifest_path [file join $dir "[file tail $exe_path].runfiles_manifest"]
    if {[file isfile $manifest_path]} {
        return $manifest_path
    }
    return ""
}

package provide runfiles 1.0
