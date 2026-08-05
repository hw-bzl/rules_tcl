"""nagelfar_syntaxdb rule"""

NagelfarSyntaxdbInfo = provider(
    doc = "A set of [Nagelfar](https://nagelfar.sourceforge.net/) syntax database files contributed by a target.",
    fields = {
        "files": "Depset[File]: Syntax database files.",
    },
)

def _nagelfar_syntaxdb_impl(ctx):
    files = depset(ctx.files.srcs)
    return [
        DefaultInfo(files = files),
        NagelfarSyntaxdbInfo(files = files),
    ]

nagelfar_syntaxdb = rule(
    doc = """\
Wraps a set of Nagelfar syntax database (`syntaxdb`) files so they can be
attached to a Tcl target via `data` and picked up by `tcl_nagelfar_aspect`
and `tcl_nagelfar_test` when linting that target or any dependent.

**Usage:**

```python
load("@rules_tcl//tcl:tcl_library.bzl", "tcl_library")
load("@rules_tcl//tcl/nagelfar:nagelfar_syntaxdb.bzl", "nagelfar_syntaxdb")

nagelfar_syntaxdb(
    name = "mylib_syntaxdb",
    srcs = ["mylib.syntaxdb.tcl"],
)

tcl_library(
    name = "mylib",
    srcs = ["mylib.tcl"],
    data = [":mylib_syntaxdb"],
)
```
""",
    implementation = _nagelfar_syntaxdb_impl,
    attrs = {
        "srcs": attr.label_list(
            doc = "Nagelfar syntax database files.",
            allow_files = True,
            mandatory = True,
        ),
    },
)
