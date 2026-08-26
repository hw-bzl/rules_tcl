"""TCL Providers"""

TclCoreInfo = provider(
    doc = "Info about a tclcore target consumed by `tcl_toolchain.tclcore`.",
    fields = {
        "include": "str: Runfiles-relative directory containing `init.tcl`, added to `auto_path`.",
        "init_tcl": "File: `init.tcl` from the tclcore tree.",
    },
)

TclLibInfo = provider(
    doc = "Info about a tcllib target consumed by `tcl_toolchain.tcllib`.",
    fields = {
        "include": "str: Runfiles-relative directory containing the top-level `pkgIndex.tcl`, added to `auto_path`.",
        "pkg_index": "File: Top-level `pkgIndex.tcl` for the tcllib tree.",
    },
)

TclInfo = provider(
    doc = "Info about a Tcl target.",
    fields = {
        "includes": "Depset[str]: A list of include paths associated with the current target.",
        "srcs": "Depset[File]: Direct source files of the current target.",
        "transitive_includes": "Depset[str]: Include paths from dependencies.",
        "transitive_srcs": "Depset[File]: Source files required at runtime from dependencies.",
    },
)
