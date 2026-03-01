"""TCL Providers"""

TclInfo = provider(
    doc = "Info about a Tcl target.",
    fields = {
        "includes": "Depset[str]: A list of include paths associated with the current target.",
        "srcs": "Depset[File]: Direct source files of the current target.",
        "transitive_includes": "Depset[str]: Include paths from dependencies.",
        "transitive_srcs": "Depset[File]: Source files required at runtime from dependencies.",
    },
)

def find_srcs(target):
    """Find all lintable source files for a given target.

    Note that generated files are ignored, and external targets are skipped.

    Args:
        target (Target): The target to collect from.

    Returns:
        list[File]: A list of lintable source files.
    """
    if TclInfo not in target:
        return []

    if target.label.workspace_root.startswith("external"):
        return []

    info = target[TclInfo]

    return [
        src
        for src in info.srcs.to_list()
        if src.is_source
    ]
