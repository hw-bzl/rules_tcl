"""Tclint toolchain rules"""

load("@rules_venv//python:py_info.bzl", "PyInfo")

TCLINT_TOOLCHAIN_TYPE = str(Label("//tcl/tclint:toolchain_type"))

def _tclint_toolchain_impl(ctx):
    return [platform_common.ToolchainInfo(
        label = ctx.label,
        tclint = ctx.attr.tclint,
    )]

tclint_toolchain = rule(
    doc = """\
A toolchain rule for configuring [tclint](https://github.com/nmoroze/tclint).

The `tclint_toolchain` rule specifies the tclint Python library used by
`tcl_tclint_aspect`, `tcl_format_aspect`, and related test rules.

Typically, you don't need to define this directly. Instead, use the bzlmod extension:

```python
tclint = use_extension("@rules_tcl//tcl/tclint:extensions.bzl", "tclint")
tclint.toolchain()
use_repo(tclint, "tclint_toolchains")
register_toolchains("@tclint_toolchains//:all")
```
""",
    implementation = _tclint_toolchain_impl,
    attrs = {
        "tclint": attr.label(
            doc = "The [`tclint`](https://github.com/nmoroze/tclint) python library.",
            mandatory = True,
        ),
    },
)

def _current_tclint_toolchain_impl(ctx):
    toolchain = ctx.toolchains[TCLINT_TOOLCHAIN_TYPE]
    tclint = toolchain.tclint
    if not tclint:
        fail("`tclint` was not provided for the toolchain in the current configuration: {}".format(
            toolchain.label,
        ))

    if PyInfo not in tclint:
        fail("`tclint` is required to be a `py_library` target which produces `PyInfo`. `{}` does not do this. Please update `{}`".format(
            tclint.label,
            toolchain.label,
        ))

    return [
        DefaultInfo(
            files = tclint[DefaultInfo].files,
            runfiles = tclint[DefaultInfo].default_runfiles,
        ),
        tclint[PyInfo],
        tclint[OutputGroupInfo],
        tclint[InstrumentedFilesInfo],
    ]

current_tclint_toolchain = rule(
    doc = "A rule for accessing the `tclint` attribute of the current `tclint_toolchain`.",
    implementation = _current_tclint_toolchain_impl,
    toolchains = [TCLINT_TOOLCHAIN_TYPE],
)
