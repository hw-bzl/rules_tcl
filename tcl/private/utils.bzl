"""tcl rule utilities"""

load(":providers.bzl", "TclInfo")

def find_srcs(target):
    """Find all lintable source files for a given target.

    Note that generated files are ignored, and external targets are skipped.
    Use `find_source_files` when you need every source file including
    those from external repositories (e.g. to feed a syntaxdb generator
    that must know about external packages' procs).

    Args:
        target (Target): The target to collect from.

    Returns:
        list[File]: A list of lintable source files.
    """
    if TclInfo not in target:
        return []

    if target.label.workspace_root.startswith("external"):
        return []

    return find_source_files(target)

def find_source_files(target):
    """Return every non-generated source `File` on `target`'s `TclInfo`.

    Unlike `find_srcs`, this does NOT skip external targets — its
    intended use is aggregation passes (e.g. Nagelfar syntaxdb
    generation) that must cover external Tcl packages so downstream
    consumers see their proc / namespace shapes. Linting passes should
    keep calling `find_srcs` so external code stays unlinted.

    Args:
        target (Target): The target to collect from.

    Returns:
        list[File]: A list of source files.
    """
    if TclInfo not in target:
        return []

    return [
        src
        for src in target[TclInfo].srcs.to_list()
        if src.is_source
    ]
