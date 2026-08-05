"""Nagelfar toolchain rules"""

NAGELFAR_TOOLCHAIN_TYPE = str(Label("//tcl/nagelfar:toolchain_type"))

def _nagelfar_toolchain_impl(ctx):
    generated_syntaxdb = ctx.actions.declare_file("{}.tcllib.syntaxdb.tcl".format(ctx.label.name))

    driver = ctx.attr._syntaxbuild_driver
    driver_runfiles = driver[DefaultInfo].default_runfiles

    args = ctx.actions.args()
    args.add(generated_syntaxdb)
    args.add(ctx.file.syntaxbuild)

    ctx.actions.run(
        mnemonic = "TcllibNagelfarSyntaxdb",
        executable = ctx.executable._syntaxbuild_driver,
        arguments = [args],
        inputs = depset([ctx.file.syntaxbuild]),
        tools = [ctx.executable._syntaxbuild_driver, driver_runfiles.files],
        outputs = [generated_syntaxdb],
        progress_message = "Generating tcllib syntaxdb %{label}",
    )

    syntaxdb = ctx.files.syntaxdb + [generated_syntaxdb]
    all_files = depset(
        [ctx.file.nagelfar, ctx.file.syntaxbuild] + syntaxdb,
    )

    return [platform_common.ToolchainInfo(
        label = ctx.label,
        nagelfar = ctx.file.nagelfar,
        syntaxbuild = ctx.file.syntaxbuild,
        syntaxdb = syntaxdb,
        extra_args = ctx.attr.extra_args,
        all_files = all_files,
    )]

nagelfar_toolchain = rule(
    doc = """\
A toolchain rule for configuring the [Nagelfar](https://nagelfar.sourceforge.net/) Tcl syntax checker.

The `nagelfar_toolchain` rule specifies the Nagelfar script, syntax database files,
and any additional Nagelfar arguments used by `tcl_nagelfar_aspect` and
`tcl_nagelfar_test` for static analysis of Tcl code.

The toolchain also generates a syntax database for the ambient `tcl_toolchain`'s
tcllib by running `syntaxbuild.tcl` under an exec-cfg `tcl_binary`. That generated
database is automatically appended to `syntaxdb` and reaches every lint action.

The `@nagelfar` hub repository (populated by the `nagelfar` module extension)
exposes the shipped script and syntax databases as labels users combine with
their own files:

```python
load("@rules_tcl//tcl/nagelfar:nagelfar_toolchain.bzl", "nagelfar_toolchain")

nagelfar_toolchain(
    name = "nagelfar_toolchain",
    nagelfar = "@nagelfar//:nagelfar",
    syntaxbuild = "@nagelfar//:syntaxbuild",
    syntaxdb = [
        "@nagelfar//:syntaxdb",
        "//path/to:my_project_syntaxdb.tcl",
    ],
    extra_args = ["-len", "100"],
)

toolchain(
    name = "toolchain",
    toolchain = ":nagelfar_toolchain",
    toolchain_type = "@rules_tcl//tcl/nagelfar:toolchain_type",
)
```

Register the toolchain in `MODULE.bazel`:

```python
nagelfar = use_extension("@rules_tcl//tcl/nagelfar:extensions.bzl", "nagelfar")
use_repo(nagelfar, "nagelfar")
register_toolchains("//path/to:toolchain")
```
""",
    implementation = _nagelfar_toolchain_impl,
    attrs = {
        "extra_args": attr.string_list(
            doc = "Additional command-line arguments forwarded to `nagelfar` on every invocation.",
        ),
        "nagelfar": attr.label(
            doc = "The `nagelfar.tcl` script.",
            allow_single_file = True,
            mandatory = True,
        ),
        "syntaxbuild": attr.label(
            doc = "The `syntaxbuild.tcl` script shipped with Nagelfar, used to snapshot the ambient tcllib into a syntax database at toolchain-build time.",
            allow_single_file = True,
            mandatory = True,
        ),
        "syntaxdb": attr.label_list(
            doc = "Nagelfar syntax database files. The tcllib syntaxdb this toolchain generates for its ambient `tcl_toolchain` is appended automatically.",
            allow_files = True,
        ),
        "_syntaxbuild_driver": attr.label(
            doc = "Exec-cfg `tcl_binary` that force-loads tcllib packages and runs `syntaxbuild.tcl` against them.",
            default = Label("//tcl/nagelfar/private:syntaxbuild_driver"),
            cfg = "exec",
            executable = True,
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
