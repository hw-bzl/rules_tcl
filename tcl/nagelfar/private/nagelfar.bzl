"""Nagelfar lint rules"""

load("//tcl/nagelfar:nagelfar_syntaxdb.bzl", "NagelfarSyntaxdbInfo")
load("//tcl/nagelfar:nagelfar_toolchain.bzl", "NAGELFAR_TOOLCHAIN_TYPE")
load("//tcl/private:providers.bzl", "TclInfo", "find_srcs")
load("//tcl/private:toolchain.bzl", "TOOLCHAIN_TYPE")

_NagelfarSyntaxdbCollectionInfo = provider(
    doc = "Internal: transitive syntaxdb files collected via `deps` and `data`.",
    fields = {
        "syntaxdbs": "Depset[File]: Syntax database files contributed by a target and its transitive graph.",
    },
)

def _rlocationpath(file, workspace_name):
    if file.short_path.startswith("../"):
        return file.short_path[len("../"):]

    return "{}/{}".format(workspace_name, file.short_path)

def _collect_dep_srcs(ctx):
    """Collect source files from Bazel deps for nagelfar context."""
    dep_srcs = []
    if hasattr(ctx.rule.attr, "deps"):
        for dep in ctx.rule.attr.deps:
            if TclInfo in dep:
                dep_info = dep[TclInfo]
                for src in dep_info.srcs.to_list():
                    if src.is_source:
                        dep_srcs.append(src)
                for src in dep_info.transitive_srcs.to_list():
                    if src.is_source:
                        dep_srcs.append(src)
    return dep_srcs

def _nagelfar_syntaxdb_collector_aspect_impl(target, ctx):
    parts = []
    if NagelfarSyntaxdbInfo in target:
        parts.append(target[NagelfarSyntaxdbInfo].files)
    for attr_name in ("deps", "data"):
        if hasattr(ctx.rule.attr, attr_name):
            for dep in getattr(ctx.rule.attr, attr_name):
                if _NagelfarSyntaxdbCollectionInfo in dep:
                    parts.append(dep[_NagelfarSyntaxdbCollectionInfo].syntaxdbs)
    return [_NagelfarSyntaxdbCollectionInfo(syntaxdbs = depset(transitive = parts))]

_nagelfar_syntaxdb_collector_aspect = aspect(
    doc = "Internal: walks `deps` and `data` to collect `NagelfarSyntaxdbInfo` files into a single depset.",
    implementation = _nagelfar_syntaxdb_collector_aspect_impl,
    attr_aspects = ["deps", "data"],
    provides = [_NagelfarSyntaxdbCollectionInfo],
)

def _tcl_nagelfar_aspect_impl(target, ctx):
    srcs = find_srcs(target)
    if not srcs:
        return []

    ignore_tags = [
        "no_tcl_nagelfar",
        "no_nagelfar",
        "no_lint",
        "nolint",
    ]
    for tag in ctx.rule.attr.tags:
        sanitized = tag.replace("-", "_").lower()
        if sanitized in ignore_tags:
            return []

    lint_srcs = [src for src in srcs if src.basename != "pkgIndex.tcl"]
    if not lint_srcs:
        return []

    dep_srcs = _collect_dep_srcs(ctx)
    graph_syntaxdbs = target[_NagelfarSyntaxdbCollectionInfo].syntaxdbs

    output = ctx.actions.declare_file("{}.nagelfar.ok".format(target.label.name))

    args = ctx.actions.args()
    args.add_all(dep_srcs, format_each = "--dep-src=%s")
    args.add_all(lint_srcs, format_each = "--src=%s")
    args.add("--marker", output)

    toolchain = ctx.toolchains[TOOLCHAIN_TYPE]
    nagelfar_toolchain = ctx.toolchains[NAGELFAR_TOOLCHAIN_TYPE]

    args.add("--nagelfar", nagelfar_toolchain.nagelfar)
    args.add_all(nagelfar_toolchain.syntaxdb, format_each = "--syntaxdb=%s")
    args.add_all(graph_syntaxdbs, format_each = "--syntaxdb=%s")
    args.add_all(nagelfar_toolchain.extra_args, format_each = "--nagelfar-arg=%s")

    ctx.actions.run(
        mnemonic = "TclNagelfar",
        executable = ctx.executable._runner,
        arguments = [args],
        inputs = depset(
            lint_srcs + dep_srcs + [nagelfar_toolchain.nagelfar] + nagelfar_toolchain.syntaxdb,
            transitive = [toolchain.all_files, graph_syntaxdbs],
        ),
        tools = [ctx.executable._runner],
        progress_message = "TclNagelfar %{label}",
        outputs = [output],
    )

    return [OutputGroupInfo(
        tcl_nagelfar_checks = depset([output]),
    )]

tcl_nagelfar_aspect = aspect(
    doc = """\
An aspect for performing Nagelfar static analysis on Tcl targets.

The `tcl_nagelfar_aspect` applies [Nagelfar](https://nagelfar.sourceforge.net/)
checks to all Tcl targets in the dependency graph. It also traverses `deps`
and `data` (via a required collector aspect) to gather any `nagelfar_syntaxdb`
targets attached to the graph, and forwards their files to Nagelfar alongside
the toolchain-shipped databases.

**Usage:**

```bash
bazel build //my:target \\
    --aspects=@rules_tcl//tcl/nagelfar:tcl_nagelfar_aspect.bzl%tcl_nagelfar_aspect \\
    --output_groups=+tcl_nagelfar_checks
```

Or configure it in your `.bazelrc`:

```bazelrc
build:nagelfar --aspects=@rules_tcl//tcl/nagelfar:tcl_nagelfar_aspect.bzl%tcl_nagelfar_aspect
build:nagelfar --output_groups=+tcl_nagelfar_checks
```

**Ignoring targets:**

To skip Nagelfar for specific targets, add one of these tags:
- `no_tcl_nagelfar`
- `no_nagelfar`
- `no_lint`
- `nolint`
""",
    implementation = _tcl_nagelfar_aspect_impl,
    requires = [_nagelfar_syntaxdb_collector_aspect],
    attrs = {
        "_runner": attr.label(
            cfg = "exec",
            executable = True,
            default = Label("//tcl/nagelfar/private:runner"),
        ),
    },
    toolchains = [
        NAGELFAR_TOOLCHAIN_TYPE,
        TOOLCHAIN_TYPE,
    ],
    required_providers = [TclInfo],
)

def _tcl_nagelfar_test_impl(ctx):
    info = ctx.attr.target[TclInfo]
    graph_syntaxdbs = ctx.attr.target[_NagelfarSyntaxdbCollectionInfo].syntaxdbs.to_list()

    srcs = [
        src
        for src in info.srcs.to_list()
        if src.basename != "pkgIndex.tcl"
    ]

    dep_srcs = [
        src
        for src in info.transitive_srcs.to_list()
        if src.is_source
    ]

    toolchain = ctx.toolchains[TOOLCHAIN_TYPE]
    nagelfar_toolchain = ctx.toolchains[NAGELFAR_TOOLCHAIN_TYPE]

    all_syntaxdbs = nagelfar_toolchain.syntaxdb + graph_syntaxdbs

    args = ctx.actions.args()
    args.set_param_file_format("multiline")
    args.add("--nagelfar", _rlocationpath(nagelfar_toolchain.nagelfar, ctx.workspace_name))
    for db in all_syntaxdbs:
        args.add("--syntaxdb", _rlocationpath(db, ctx.workspace_name))
    for extra in nagelfar_toolchain.extra_args:
        args.add("--nagelfar-arg", extra)
    for dep_src in dep_srcs:
        args.add("--dep-src", _rlocationpath(dep_src, ctx.workspace_name))
    args.add_all([
        "--src={}".format(_rlocationpath(src, ctx.workspace_name))
        for src in srcs
    ])

    args_file = ctx.actions.declare_file("{}.args.txt".format(ctx.label.name))
    ctx.actions.write(
        output = args_file,
        content = args,
    )

    runner = ctx.executable._runner
    executable = ctx.actions.declare_file("{}.{}".format(ctx.label.name, runner.extension).rstrip("."))
    ctx.actions.symlink(
        output = executable,
        target_file = runner,
        is_executable = True,
    )

    nagelfar_files = [nagelfar_toolchain.nagelfar] + all_syntaxdbs

    return [
        DefaultInfo(
            executable = executable,
            runfiles = ctx.runfiles(
                files = srcs + dep_srcs + nagelfar_files + [args_file],
                transitive_files = toolchain.all_files,
            ).merge(
                ctx.attr._runner[DefaultInfo].default_runfiles,
            ),
        ),
        RunEnvironmentInfo(
            environment = {
                "RULES_TCL_NAGELFAR_ARGS_FILE": _rlocationpath(args_file, ctx.workspace_name),
            },
        ),
    ]

tcl_nagelfar_test = rule(
    doc = """\
A test rule for performing Nagelfar static analysis on a Tcl target.

**Usage:**

```python
load("@rules_tcl//tcl/nagelfar:tcl_nagelfar_test.bzl", "tcl_nagelfar_test")

tcl_nagelfar_test(
    name = "mylib_nagelfar",
    target = ":mylib",
)
```
""",
    implementation = _tcl_nagelfar_test_impl,
    test = True,
    toolchains = [
        NAGELFAR_TOOLCHAIN_TYPE,
        TOOLCHAIN_TYPE,
    ],
    attrs = {
        "target": attr.label(
            doc = "The Tcl target to perform Nagelfar analysis on.",
            aspects = [_nagelfar_syntaxdb_collector_aspect],
            providers = [TclInfo],
            mandatory = True,
        ),
        "_runner": attr.label(
            cfg = "exec",
            executable = True,
            default = Label("//tcl/nagelfar/private:runner"),
        ),
    },
)
