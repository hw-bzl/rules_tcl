"""Tclint lint and format rules"""

load("//tcl/private:providers.bzl", "TclInfo", "find_srcs")

def _rlocationpath(file, workspace_name):
    if file.short_path.startswith("../"):
        return file.short_path[len("../"):]

    return "{}/{}".format(workspace_name, file.short_path)

def _tcl_tclint_aspect_impl(target, ctx):
    srcs = find_srcs(target)
    if not srcs:
        return []

    ignore_tags = [
        "no_tcl_lint",
        "no_tclint",
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

    config = ctx.file._config
    output = ctx.actions.declare_file("{}.tclint.ok".format(target.label.name))

    args = ctx.actions.args()
    args.add_all(lint_srcs, format_each = "--src=%s")
    args.add("--config", config)
    args.add("--marker", output)

    ctx.actions.run(
        mnemonic = "TclLint",
        executable = ctx.executable._linter,
        arguments = [args],
        inputs = depset(lint_srcs + [config]),
        progress_message = "TclLint %{label}",
        outputs = [output],
    )

    return [OutputGroupInfo(
        tcl_tclint_checks = depset([output]),
    )]

tcl_tclint_aspect = aspect(
    doc = """\
An aspect for performing tclint linting checks on Tcl targets.

Uses [tclint](https://github.com/nmoroze/tclint) to check for code quality issues.

**Usage:**

```bash
bazel build //my:target \\
    --aspects=@rules_tcl//tcl/tclint:tcl_tclint_aspect.bzl%tcl_tclint_aspect \\
    --output_groups=+tcl_tclint_checks
```

**Ignoring targets:**

To skip tclint for specific targets, add one of these tags:
- `no_tcl_lint`
- `no_tclint`
- `no_lint`
- `nolint`
""",
    implementation = _tcl_tclint_aspect_impl,
    attrs = {
        "_config": attr.label(
            allow_single_file = True,
            default = Label("//tcl/tclint:config"),
        ),
        "_linter": attr.label(
            cfg = "exec",
            executable = True,
            default = Label("//tcl/tclint/private:linter"),
        ),
    },
    required_providers = [TclInfo],
)

def _tcl_tclint_test_impl(ctx):
    srcs = [
        src
        for src in ctx.attr.target[TclInfo].srcs.to_list()
        if src.basename != "pkgIndex.tcl"
    ]

    config = ctx.file._config

    args = ctx.actions.args()
    args.set_param_file_format("multiline")
    args.add("--config", _rlocationpath(config, ctx.workspace_name))
    args.add_all([
        "--src={}".format(_rlocationpath(src, ctx.workspace_name))
        for src in srcs
    ])

    args_file = ctx.actions.declare_file("{}.args.txt".format(ctx.label.name))
    ctx.actions.write(
        output = args_file,
        content = args,
    )

    runner = ctx.executable._linter
    executable = ctx.actions.declare_file("{}.{}".format(ctx.label.name, runner.extension).rstrip("."))
    ctx.actions.symlink(
        output = executable,
        target_file = runner,
        is_executable = True,
    )

    return [
        DefaultInfo(
            executable = executable,
            runfiles = ctx.runfiles(
                files = srcs + [config, args_file],
            ).merge(
                ctx.attr._linter[DefaultInfo].default_runfiles,
            ),
        ),
        RunEnvironmentInfo(
            environment = {
                "RULES_TCL_LINT_ARGS_FILE": _rlocationpath(args_file, ctx.workspace_name),
            },
        ),
    ]

tcl_tclint_test = rule(
    doc = """\
A test rule for performing tclint linting checks on a Tcl target.

**Usage:**

```python
load("@rules_tcl//tcl/tclint:tcl_tclint_test.bzl", "tcl_tclint_test")

tcl_tclint_test(
    name = "mylib_tclint",
    target = ":mylib",
)
```
""",
    implementation = _tcl_tclint_test_impl,
    test = True,
    attrs = {
        "target": attr.label(
            doc = "The Tcl target to perform linting on.",
            providers = [TclInfo],
            mandatory = True,
        ),
        "_config": attr.label(
            allow_single_file = True,
            default = Label("//tcl/tclint:config"),
        ),
        "_linter": attr.label(
            cfg = "exec",
            executable = True,
            default = Label("//tcl/tclint/private:linter"),
        ),
    },
)

def _tcl_tclint_fmt_aspect_impl(target, ctx):
    srcs = find_srcs(target)
    if not srcs:
        return []

    ignore_tags = [
        "no_tcl_format",
        "no_tclformat",
        "no_tclfmt",
        "noformat",
        "nofmt",
    ]
    for tag in ctx.rule.attr.tags:
        sanitized = tag.replace("-", "_").lower()
        if sanitized in ignore_tags:
            return []

    config = ctx.file._config
    output = ctx.actions.declare_file("{}.tclfmt.ok".format(target.label.name))

    args = ctx.actions.args()
    args.add_all(srcs, format_each = "--src=%s")
    args.add("--config", config)
    args.add("--marker", output)

    ctx.actions.run(
        mnemonic = "TclFormat",
        executable = ctx.executable._formatter,
        arguments = [args],
        inputs = depset(srcs + [config]),
        progress_message = "TclFormat %{label}",
        outputs = [output],
    )

    return [OutputGroupInfo(
        tcl_tclint_fmt_checks = depset([output]),
    )]

tcl_tclint_fmt_aspect = aspect(
    doc = """\
An aspect for performing formatting checks on Tcl targets.

Uses [tclint](https://github.com/nmoroze/tclint) to verify formatting.

**Usage:**

```bash
bazel build //my:target \\
    --aspects=@rules_tcl//tcl/tclint:tcl_tclint_fmt_aspect.bzl%tcl_tclint_fmt_aspect \\
    --output_groups=+tcl_tclint_fmt_checks
```

**Ignoring targets:**

To skip format checking for specific targets, add one of these tags:
- `no_tcl_format`
- `no_tclformat`
- `no_tclfmt`
- `noformat`
- `nofmt`
""",
    implementation = _tcl_tclint_fmt_aspect_impl,
    attrs = {
        "_config": attr.label(
            allow_single_file = True,
            default = Label("//tcl/tclint:config"),
        ),
        "_formatter": attr.label(
            cfg = "exec",
            executable = True,
            default = Label("//tcl/tclint/private:format_checker"),
        ),
    },
    required_providers = [TclInfo],
)

def _tcl_tclint_fmt_test_impl(ctx):
    srcs = [
        src
        for src in ctx.attr.target[TclInfo].srcs.to_list()
        if src.basename != "pkgIndex.tcl"
    ]

    config = ctx.file._config

    args = ctx.actions.args()
    args.set_param_file_format("multiline")
    args.add("--config", _rlocationpath(config, ctx.workspace_name))
    args.add_all([
        "--src={}".format(_rlocationpath(src, ctx.workspace_name))
        for src in srcs
    ])

    args_file = ctx.actions.declare_file("{}.args.txt".format(ctx.label.name))
    ctx.actions.write(
        output = args_file,
        content = args,
    )

    runner = ctx.executable._formatter
    executable = ctx.actions.declare_file("{}.{}".format(ctx.label.name, runner.extension).rstrip("."))
    ctx.actions.symlink(
        output = executable,
        target_file = runner,
        is_executable = True,
    )

    return [
        DefaultInfo(
            executable = executable,
            runfiles = ctx.runfiles(
                files = srcs + [config, args_file],
            ).merge(
                ctx.attr._formatter[DefaultInfo].default_runfiles,
            ),
        ),
        RunEnvironmentInfo(
            environment = {
                "RULES_TCL_FORMAT_ARGS_FILE": _rlocationpath(args_file, ctx.workspace_name),
            },
        ),
    ]

tcl_tclint_fmt_test = rule(
    doc = """\
A test rule for performing formatting checks on a Tcl target.

**Usage:**

```python
load("@rules_tcl//tcl/tclint:tcl_tclint_fmt_test.bzl", "tcl_tclint_fmt_test")

tcl_tclint_fmt_test(
    name = "mylib_format",
    target = ":mylib",
)
```
""",
    implementation = _tcl_tclint_fmt_test_impl,
    test = True,
    attrs = {
        "target": attr.label(
            doc = "The Tcl target to perform formatting checks on.",
            providers = [TclInfo],
            mandatory = True,
        ),
        "_config": attr.label(
            allow_single_file = True,
            default = Label("//tcl/tclint:config"),
        ),
        "_formatter": attr.label(
            cfg = "exec",
            executable = True,
            default = Label("//tcl/tclint/private:format_checker"),
        ),
    },
)
