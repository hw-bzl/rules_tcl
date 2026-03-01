"""Tcl rules"""

load(":providers.bzl", "TclInfo")
load(":toolchain.bzl", "TOOLCHAIN_TYPE")

_COMMON_ATTRS = {
    "data": attr.label_list(
        doc = "Files needed by this rule at runtime. May list file or rule targets. Generally allows any target.",
        allow_files = True,
    ),
    "deps": attr.label_list(
        doc = "Other Tcl packages to link to the current target.",
        providers = [TclInfo],
    ),
    "srcs": attr.label_list(
        doc = "The list of source (`.tcl`) files that are processed to create the target.",
        allow_files = [".tcl"],
        mandatory = True,
        allow_empty = False,
    ),
}

_EXECUTABLE_ATTRS = _COMMON_ATTRS | {
    "env": attr.string_dict(
        doc = "Dictionary of strings; values are subject to `$(location)` and \"Make variable\" substitution.",
    ),
    "main": attr.label(
        doc = (
            "The name of the source file that is the main entry point of the application. " +
            "This file must also be listed in `srcs`. If left unspecified, `name` is used " +
            "instead. If `name` does not match any filename in `srcs`, `main` must be specified. "
        ),
        allow_single_file = True,
    ),
    "_bash_runfiles": attr.label(
        cfg = "target",
        default = Label("@bazel_tools//tools/bash/runfiles"),
    ),
    "_entrypoint": attr.label(
        doc = "The executable entrypoint.",
        allow_single_file = True,
        default = Label("//tcl/private:entrypoint.tcl"),
    ),
    "_windows_constraint": attr.label(
        default = Label("@platforms//os:windows"),
    ),
    "_wrapper_template": attr.label(
        allow_single_file = True,
        default = Label("//tcl/private:binary_wrapper.tpl"),
    ),
}

_TEST_ATTRS = _EXECUTABLE_ATTRS | {
    "env_inherit": attr.string_list(
        doc = """\
Specifies additional environment variables to inherit from the external environment.

This attribute is only available for `tcl_test` rules. When the test is executed by
`bazel test`, these environment variables from the host environment will be passed
through to the test.

Example:
```python
tcl_test(
    name = "my_test",
    srcs = ["test.tcl"],
    env_inherit = [
        "PATH",
        "HOME",
        "USER",
    ],
)
```

This is useful when tests need access to system tools or user-specific configuration.
""",
    ),
}

def _create_dep_info(*, ctx, deps):
    """Construct dependency info required for building `TclInfo`

    Args:
        ctx (ctx): The rule's context object.
        deps (list): A list of python dependency targets

    Returns:
        struct: Dependency info.
    """
    runfiles = ctx.runfiles()
    include_workspaces = []
    includes = []
    srcs = []
    for dep in deps:
        info = dep[TclInfo]
        srcs.append(info.srcs)
        srcs.append(info.transitive_srcs)
        includes.append(info.includes)
        workspace_name = dep.label.workspace_name
        if not workspace_name:
            workspace_name = ctx.workspace_name
        include_workspaces.append(workspace_name)
        runfiles = runfiles.merge(dep[DefaultInfo].default_runfiles)

    return struct(
        transitive_includes = depset(include_workspaces, transitive = includes),
        transitive_srcs = depset(transitive = srcs, order = "postorder"),
        # Runfiles from dependencies.
        runfiles = runfiles,
    )

def _create_tcl_info(*, ctx, includes, srcs, dep_info = None):
    """Construct a `TclInfo` provider

    Args:
        ctx (ctx): The rule's context object.
        includes (list): The raw `includes` attribute.
        srcs (list): A list of python (`.tcl`) source files.
        dep_info (struct, optional): Dependency info from the current target.

    Returns:
        TclInfo: A `TclInfo` provider.
    """
    if not dep_info:
        dep_info = _create_dep_info(ctx = ctx, deps = [])

    return TclInfo(
        includes = depset(includes),
        transitive_includes = dep_info.transitive_includes,
        srcs = depset(
            srcs,
            transitive = [],
            order = "postorder",
        ),
        transitive_srcs = dep_info.transitive_srcs,
    )

def _find_pkg_index(srcs, label, workspace_name):
    top_pkg_index = None
    for file in srcs:
        if file.basename == "pkgIndex.tcl":
            if not top_pkg_index:
                top_pkg_index = file
                continue

            if len(top_pkg_index.short_path) > len(file.short_path):
                top_pkg_index = file

    if top_pkg_index:
        include = _rlocationpath(top_pkg_index, workspace_name)[:-len("/pkgIndex.tcl")]
        return struct(
            pkg_index = top_pkg_index,
            include = include,
        )

    fail("No `pkgIndex.tcl` source file was found in `srcs` of `{}`".format(label))

def _tcl_library_impl(ctx):
    dep_info = _create_dep_info(
        ctx = ctx,
        deps = ctx.attr.deps,
    )

    runfiles = ctx.runfiles(
        files = ctx.files.srcs + ctx.files.data,
    ).merge_all(
        [
            dep_info.runfiles,
        ] + [
            target[DefaultInfo].default_runfiles
            for target in ctx.attr.data
        ],
    )

    pkg_info = _find_pkg_index(ctx.files.srcs, ctx.label, ctx.workspace_name)

    return [
        DefaultInfo(
            files = depset(ctx.files.srcs),
            runfiles = runfiles,
        ),
        _create_tcl_info(
            ctx = ctx,
            includes = [pkg_info.include],
            srcs = ctx.files.srcs,
            dep_info = dep_info,
        ),
        coverage_common.instrumented_files_info(
            ctx,
            dependency_attributes = ["deps"],
            extensions = ["tcl"],
            source_attributes = ["srcs"],
        ),
    ]

tcl_library = rule(
    doc = """\
A Tcl library that can be depended upon by other Tcl targets.

A `tcl_library` represents a Tcl package that can be imported using Tcl's `package require` command.
The library must include a `pkgIndex.tcl` file in its `srcs` attribute, which defines the package
metadata and how to load the package.

**Important**: The `pkgIndex.tcl` file must be included in the `srcs` attribute. This file is used
by Tcl's package system to locate and load the package.

Example:

```python
load("@rules_tcl//tcl:defs.bzl", "tcl_library")

tcl_library(
    name = "mylib",
    srcs = [
        "mylib.tcl",
        "pkgIndex.tcl",
    ],
    deps = [
        ":otherlib",  # Another tcl_library
    ],
    visibility = ["//visibility:public"],
)
```

The library can then be used as a dependency in other targets:

```python
tcl_binary(
    name = "app",
    srcs = ["app.tcl"],
    deps = [":mylib"],
)
```
""",
    implementation = _tcl_library_impl,
    attrs = _COMMON_ATTRS,
    provides = [TclInfo],
)

def _compute_main(ctx, srcs, main = None):
    """Determine the main entrypoint for executable rules.

    Args:
        ctx (ctx): The rule's context object.
        srcs (list): A list of File objects.
        main (File, optional): An explicit contender for the main entrypoint.

    Returns:
        File: The file to use for the main entrypoint.
    """
    if main:
        if main not in srcs:
            fail("`main` was not found in `srcs`. Please add `{}` to `srcs` for {}".format(
                main.path,
                ctx.label,
            ))
        return main

    if len(srcs) == 1:
        main = srcs[0]
    else:
        for src in srcs:
            if main:
                fail("Multiple files match candidates for `main`. Please explicitly specify which to use for {}".format(
                    ctx.label,
                ))

            basename = src.basename[:-len(".tcl")]
            if basename == ctx.label.name:
                main = src

    if not main:
        fail("`main` and no `srcs` were specified. Please update {}".format(
            ctx.label,
        ))

    return main

def _create_run_environment_info(ctx, env, env_inherit, targets):
    """Create an environment info provider

    This macro performs location expansions.

    Args:
        ctx (ctx): The rule's context object.
        env (dict): Environment variables to set.
        env_inherit (list): Environment variables to inehrit from the host.
        targets (List[Target]): Targets to use in location expansion.

    Returns:
        RunEnvironmentInfo: The provider.
    """

    known_variables = {}
    for target in ctx.attr.toolchains:
        if platform_common.TemplateVariableInfo in target:
            variables = getattr(target[platform_common.TemplateVariableInfo], "variables", {})
            known_variables.update(variables)

    expanded_env = {}
    for key, value in env.items():
        expanded_env[key] = ctx.expand_make_variables(
            key,
            ctx.expand_location(value, targets),
            known_variables,
        )

    workspace_name = ctx.label.workspace_name
    if not workspace_name:
        workspace_name = ctx.workspace_name

    if not workspace_name:
        workspace_name = "_main"

    # Needed for bzlmod-aware runfiles resolution.
    expanded_env["REPOSITORY_NAME"] = workspace_name

    return RunEnvironmentInfo(
        environment = expanded_env,
        inherited_environment = env_inherit,
    )

def _rlocationpath(file, workspace_name):
    if file.short_path.startswith("../"):
        return file.short_path[len("../"):]

    return "{}/{}".format(workspace_name, file.short_path)

def _tcl_binary_impl(ctx):
    toolchain = ctx.toolchains[TOOLCHAIN_TYPE]

    main = _compute_main(
        ctx = ctx,
        main = ctx.file.main,
        srcs = ctx.files.srcs,
    )

    extension = ".sh"
    workspace_name = ctx.label.workspace_name
    if not workspace_name:
        workspace_name = ctx.workspace_name
    if not workspace_name:
        workspace_name = "_main"

    include_paths = depset(
        [workspace_name],
        transitive = [dep[TclInfo].includes for dep in ctx.attr.deps] + [toolchain.includes],
    )

    is_windows = ctx.target_platform_has_constraint(ctx.attr._windows_constraint[platform_common.ConstraintValueInfo])
    if is_windows:
        extension = ".bat"

    output = ctx.actions.declare_file("{}{}".format(ctx.label.name, extension))
    config = ctx.actions.declare_file("{}.config.json".format(ctx.label.name))

    dep_info = _create_dep_info(
        ctx = ctx,
        deps = ctx.attr.deps,
    )

    runfiles = dep_info.runfiles.merge_all([
        ctx.runfiles(
            files = [ctx.file._entrypoint] + ctx.files.srcs,
            transitive_files = depset(transitive = [toolchain.all_files]),
        ),
        ctx.attr._bash_runfiles.default_runfiles,
    ])

    ctx.actions.write(
        output = config,
        content = json.encode_indent({
            "includes": include_paths.to_list(),
            "runfiles": [
                _rlocationpath(src, ctx.workspace_name)
                for src in runfiles.files.to_list()
            ],
        }),
    )

    tcl_info = _create_tcl_info(
        ctx = ctx,
        includes = [workspace_name],
        srcs = ctx.files.srcs,
        dep_info = dep_info,
    )

    ctx.actions.expand_template(
        template = ctx.file._wrapper_template,
        output = output,
        substitutions = {
            "{config}": _rlocationpath(config, ctx.workspace_name),
            "{entrypoint}": _rlocationpath(ctx.file._entrypoint, ctx.workspace_name),
            "{init_tcl}": _rlocationpath(toolchain.init_tcl, ctx.workspace_name),
            "{interpreter}": _rlocationpath(toolchain.tclsh, ctx.workspace_name),
            "{main}": _rlocationpath(main, ctx.workspace_name),
            "{tcllib_pkg_index}": _rlocationpath(toolchain.tcllib_pkg_index, ctx.workspace_name),
        },
        is_executable = True,
    )

    data_runfiles = []
    for target in ctx.attr.data:
        if DefaultInfo in target:
            data_runfiles.append(target[DefaultInfo].default_runfiles)

    return [
        tcl_info,
        DefaultInfo(
            executable = output,
            files = depset([output]),
            runfiles = runfiles.merge_all(
                [ctx.runfiles([config, output] + ctx.files.data)] + data_runfiles,
            ),
        ),
        coverage_common.instrumented_files_info(
            ctx,
            dependency_attributes = ["deps"],
            extensions = ["tcl"],
            source_attributes = ["srcs"],
        ),
        _create_run_environment_info(
            ctx = ctx,
            env = ctx.attr.env,
            env_inherit = getattr(ctx.attr, "env_inherit", []),
            targets = ctx.attr.data,
        ),
    ]

tcl_binary = rule(
    doc = """\
A `tcl_binary` is an executable Tcl program consisting of a collection of
`.tcl` source files (possibly belonging to other `tcl_library` rules), a `*.runfiles`
directory tree containing all the code and data needed by the program at run-time,
and a stub script that starts up the program with the correct initial environment
and data.

```python
load("@rules_tcl//tcl:defs.bzl", "tcl_binary")

tcl_binary(
    name = "foo",
    srcs = ["foo.tcl"],
    deps = [
        ":bar",  # a tcl_library
    ],
)
```
""",
    implementation = _tcl_binary_impl,
    attrs = _EXECUTABLE_ATTRS,
    executable = True,
    toolchains = [
        TOOLCHAIN_TYPE,
    ],
    provides = [TclInfo],
)

def _tcl_test_impl(ctx):
    return _tcl_binary_impl(ctx)

tcl_test = rule(
    doc = """\
A test rule for Tcl code that can be executed with `bazel test`.

A `tcl_test` is similar to a `tcl_binary` but is designed for testing. It supports all the same
attributes as `tcl_binary`, plus additional test-specific features like environment variable
inheritance.

Tests are executed by Bazel's test runner and can be run with:

```bash
bazel test //path/to:my_test
```

Example:

```python
load("@rules_tcl//tcl:defs.bzl", "tcl_test")

tcl_test(
    name = "my_test",
    srcs = ["test.tcl"],
    deps = [
        ":mylib",  # The library being tested
    ],
    env = {
        "TEST_MODE": "1",
    },
    env_inherit = ["PATH"],  # Inherit PATH from the environment
)
```

The test can use Tcl's standard testing frameworks or custom test code. Test failures are
detected by non-zero exit codes.
""",
    implementation = _tcl_test_impl,
    attrs = _TEST_ATTRS,
    test = True,
    toolchains = [
        TOOLCHAIN_TYPE,
    ],
    provides = [TclInfo],
)
