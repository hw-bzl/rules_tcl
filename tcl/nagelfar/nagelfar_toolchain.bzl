"""Nagelfar toolchain rules"""

NAGELFAR_TOOLCHAIN_TYPE = str(Label("//tcl/nagelfar:toolchain_type"))

def _nagelfar_toolchain_impl(ctx):
    all_files = depset(
        [ctx.file.nagelfar] + ctx.files.syntaxdb,
    )

    return [platform_common.ToolchainInfo(
        label = ctx.label,
        nagelfar = ctx.file.nagelfar,
        syntaxdb = ctx.files.syntaxdb,
        all_files = all_files,
    )]

nagelfar_toolchain = rule(
    doc = """\
A toolchain rule for configuring the [Nagelfar](https://nagelfar.sourceforge.net/) Tcl syntax checker.

The `nagelfar_toolchain` rule specifies the Nagelfar script and syntax database files
used by `tcl_nagelfar_aspect` and `tcl_nagelfar_test` for static analysis of Tcl code.

Typically, you don't need to define this directly. Instead, use the bzlmod extension:

```python
nagelfar = use_extension("@rules_tcl//tcl/nagelfar:extensions.bzl", "nagelfar")
nagelfar.toolchain()
use_repo(nagelfar, "nagelfar_toolchains")
register_toolchains("@nagelfar_toolchains//:all")
```
""",
    implementation = _nagelfar_toolchain_impl,
    attrs = {
        "nagelfar": attr.label(
            doc = "The `nagelfar.tcl` script.",
            allow_single_file = True,
            mandatory = True,
        ),
        "syntaxdb": attr.label(
            doc = "Nagelfar syntax database files.",
            allow_files = True,
        ),
    },
)

def _current_nagelfar_toolchain_impl(ctx):
    toolchain = ctx.toolchains[NAGELFAR_TOOLCHAIN_TYPE]

    all_files = toolchain.all_files

    return [
        DefaultInfo(
            files = all_files,
            runfiles = ctx.runfiles(transitive_files = all_files),
        ),
    ]

current_nagelfar_toolchain = rule(
    doc = "A rule for accessing the current `nagelfar_toolchain`.",
    implementation = _current_nagelfar_toolchain_impl,
    toolchains = [NAGELFAR_TOOLCHAIN_TYPE],
)
