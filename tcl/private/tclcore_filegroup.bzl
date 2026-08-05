"""Public rule for tclcore."""

load(":providers.bzl", "TclCoreInfo")
load(":toolchain.bzl", "rlocationpath")

def _tclcore_filegroup_impl(ctx):
    init_tcl = None
    for src in ctx.files.srcs:
        if src.basename == "init.tcl":
            init_tcl = src
            break

    if not init_tcl:
        fail("`{}`: no `init.tcl` found in `srcs`.".format(ctx.label))

    include = rlocationpath(init_tcl, ctx.workspace_name)[:-len("/init.tcl")]

    return [
        DefaultInfo(
            files = depset(ctx.files.srcs),
            runfiles = ctx.runfiles(files = ctx.files.srcs),
        ),
        TclCoreInfo(
            init_tcl = init_tcl,
            include = include,
        ),
    ]

tclcore_filegroup = rule(
    doc = "Wraps a tclcore source tree and surfaces `init.tcl` via `TclCoreInfo` for consumption by `tcl_toolchain.tclcore`.",
    implementation = _tclcore_filegroup_impl,
    attrs = {
        "srcs": attr.label_list(
            allow_files = True,
            doc = "Files that make up the tclcore tree. Must contain an `init.tcl`.",
            mandatory = True,
        ),
    },
)
