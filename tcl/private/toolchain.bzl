"""tcl toolchain rules"""

TOOLCHAIN_TYPE = str(Label("//tcl:toolchain_type"))

_TEMPLATE_SUFFIXES = [".tpl", ".template", ".tmpl", ".in"]

def _derive_wrapper_extension(template_file):
    """Extension for the wrapper produced from `template_file`.

    Strips a single known template suffix (`.tpl`, `.template`, `.tmpl`, `.in`)
    from the template's basename and returns whatever extension remains. E.g.
    `binary_wrapper.sh.tpl` -> `.sh`; `wrapper.bat.template` -> `.bat`;
    `wrapper.sh` (no template suffix) -> `.sh`.
    """
    name = template_file.basename
    for suffix in _TEMPLATE_SUFFIXES:
        if name.endswith(suffix):
            name = name[:-len(suffix)]
            break
    dot = name.rfind(".")
    if dot == -1:
        return ""
    return name[dot:]

def _rlocationpath(file, workspace_name):
    if file.short_path.startswith("../"):
        return file.short_path[len("../"):]

    return "{}/{}".format(workspace_name, file.short_path)

def _parse_tclcore(label, workspace_name, target):
    for file in target[DefaultInfo].files.to_list():
        if file.basename == "init.tcl":
            include = _rlocationpath(file, workspace_name)[:-len("/init.tcl")]
            return struct(
                include = include,
                init_tcl = file,
            )

    fail("Failed to parse `tclcore` from `{}` for `{}`".format(target.label, label))

def _parse_tcllib(label, workspace_name, target):
    top_pkg_index = None
    for file in target[DefaultInfo].files.to_list():
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

    fail("Failed to parse `tcllib` from `{}` for `{}`".format(target.label, label))

def _tcl_toolchain_impl(ctx):
    make_variable_info = platform_common.TemplateVariableInfo({
        "TCLSH": ctx.executable.tclsh.short_path,
    })

    all_transitive = [
        ctx.attr.tclsh[DefaultInfo].default_runfiles.files,
        ctx.attr.tclsh[DefaultInfo].files,
    ]
    if ctx.attr.tclcore:
        all_transitive.append(ctx.attr.tclcore[DefaultInfo].default_runfiles.files)
        all_transitive.append(ctx.attr.tclcore[DefaultInfo].files)
    if ctx.attr.tcllib:
        all_transitive.append(ctx.attr.tcllib[DefaultInfo].default_runfiles.files)
        all_transitive.append(ctx.attr.tcllib[DefaultInfo].files)

    includes = []
    init_tcl = None
    tcllib_pkg_index = None
    if ctx.attr.tclcore:
        tcl_core_info = _parse_tclcore(ctx.label, ctx.workspace_name, ctx.attr.tclcore)
        includes.append(tcl_core_info.include)
        init_tcl = tcl_core_info.init_tcl
    if ctx.attr.tcllib:
        tcllib_info = _parse_tcllib(ctx.label, ctx.workspace_name, ctx.attr.tcllib)
        includes.append(tcllib_info.include)
        tcllib_pkg_index = tcllib_info.pkg_index

    wrapper_entrypoint = ctx.file.wrapper_entrypoint
    wrapper_runfiles = ctx.attr.wrapper_template[DefaultInfo].default_runfiles
    if wrapper_entrypoint:
        wrapper_runfiles = wrapper_runfiles.merge_all([
            ctx.attr.wrapper_entrypoint[DefaultInfo].default_runfiles,
            ctx.runfiles(files = [wrapper_entrypoint]),
        ])

    all_files = depset(transitive = all_transitive)

    return [
        platform_common.ToolchainInfo(
            label = ctx.label,
            make_variable_info = make_variable_info,
            tclsh = ctx.executable.tclsh,
            includes = depset(includes),
            init_tcl = init_tcl,
            tcllib_pkg_index = tcllib_pkg_index,
            all_files = all_files,
            _wrapper_template = ctx.file.wrapper_template,
            _wrapper_extension = _derive_wrapper_extension(ctx.file.wrapper_template),
            _wrapper_entrypoint = wrapper_entrypoint,
            _wrapper_runfiles = wrapper_runfiles,
        ),
        make_variable_info,
    ]

tcl_toolchain = rule(
    doc = """\
A toolchain rule that defines the Tcl interpreter, libraries, and executable wrapper used
to build `tcl_binary`, `tcl_library`, and `tcl_test` targets.

## Registering a toolchain

`rules_tcl` does not register a toolchain for you. Add the following to your `MODULE.bazel`
to use the default (a stock `tclsh` and tcllib, with the built-in shell/batch wrapper):

```python
register_toolchains("@rules_tcl//tcl/toolchain")
```

If you need a custom toolchain (e.g. a different Tcl version, or a wrapper that dispatches
into a different host interpreter), define your own:

```python
load("@rules_tcl//tcl:tcl_toolchain.bzl", "tcl_toolchain")

tcl_toolchain(
    name = "my_tcl_toolchain",
    tclsh = "@my_tcl//:tclsh",
    tclcore = "@my_tcl//:tclcore",  # optional
    tcllib = "@tcllib//:tcllib",    # optional
    wrapper_template = "//path/to:my_wrapper_bundle",
    wrapper_entrypoint = "//path/to:my_entrypoint.tcl",  # optional
)
```

`tclcore` and `tcllib` may be omitted when the interpreter ships them itself.
`wrapper_entrypoint` is optional when the wrapper does not need a bootstrap script.

The template's own `DefaultInfo.default_runfiles` are merged into every produced binary,
so a template that needs a helper library (e.g. `@rules_shell//shell/runfiles` for sh,
`@rules_batch//batch/runfiles` for batch) should be declared via a `filegroup` that lists
the helper under `data`:

```python
filegroup(
    name = "my_wrapper_bundle",
    srcs = ["my_wrapper.sh.tpl"],
    data = ["@rules_shell//shell/runfiles"],
)
```

The same is true for `wrapper_entrypoint` — a `filegroup` around the entrypoint can carry
extra runtime data it needs at execution.

The extension appended to the produced wrapper is derived from the template's filename by
stripping a single known template suffix (`.tpl`, `.template`, `.tmpl`, `.in`). Name the
template `<something>.<ext>.<template-suffix>` — e.g. `my_wrapper.sh.tpl` yields `.sh`,
`my_wrapper.bat.template` yields `.bat`.

## `ToolchainInfo` contract

The rule returns a `platform_common.ToolchainInfo` with the following fields. Non-underscore
fields are the public contract that consumers (including third-party rules that operate
over Tcl targets) may read. Underscore-prefixed fields are internal to the built-in
`tcl_binary` / `tcl_test` implementation — third-party rules that want a materially
different wrapper should carry their own template rather than reach into them.

| Field                | Type                                   | Access   | Notes                                                              |
|----------------------|----------------------------------------|----------|--------------------------------------------------------------------|
| `tclsh`              | `File`                                 | public   | Executable of the interpreter that will run the produced binaries. |
| `includes`           | `depset[str]`                          | public   | Runfiles-relative include paths implicitly on `auto_path`.         |
| `init_tcl`           | `File \\| None`                        | public   | `init.tcl` from tclcore, or `None`.                                |
| `tcllib_pkg_index`   | `File \\| None`                        | public   | tcllib's top-level `pkgIndex.tcl`, or `None`.                      |
| `all_files`          | `depset[File]`                         | public   | Runtime files merged into every produced target.                   |
| `make_variable_info` | `platform_common.TemplateVariableInfo` | public   | Exposes `$(TCLSH)` for `env` on downstream rules.                  |
| `_wrapper_*`         | (various)                              | internal | Wrapper template, entrypoint, and derived extension.               |

## Wrapper template contract

The built-in `tcl_binary` / `tcl_test` expand `wrapper_template` once per target into a
file named `<target><wrapper_extension>` and set it as the target's executable. The
template supports these substitutions; values whose backing toolchain field is unset
expand to the empty string, so a template can simply omit lines it does not need:

| Substitution         | Value                                                                                 | Empty when                   |
|----------------------|---------------------------------------------------------------------------------------|------------------------------|
| `{interpreter}`      | Runfiles path (rlocation) of `tclsh`.                                                 | never                        |
| `{entrypoint}`       | Runfiles path of `wrapper_entrypoint`.                                                | `wrapper_entrypoint` unset   |
| `{config}`           | Runfiles path of a per-target JSON config (see below).                                | never                        |
| `{main}`             | Runfiles path of the target's entry `.tcl` (resolved from `main` / `srcs`).           | never                        |
| `{init_tcl}`         | Runfiles path of tclcore's `init.tcl`.                                                | `tclcore` unset              |
| `{tcllib_pkg_index}` | Runfiles path of tcllib's top-level `pkgIndex.tcl`.                                   | `tcllib` unset               |
| `{auto_path}`        | Tcl-list literal (brace-quoted) of every include path visible to the target — the target's own workspace, each dep's `TclInfo.includes`, and the toolchain's `includes`. Suitable to `lappend` onto `auto_path`. | never |

The `{config}` file is JSON with this shape:

```json
{
  "includes": ["workspace_name", "workspace_name/path/to/lib", "..."],
  "runfiles": ["workspace_name/path/to/file", "..."]
}
```

`includes` is the same set of runfiles-relative paths surfaced through `{auto_path}`;
`runfiles` is every file merged into the target's runfiles. The default `entrypoint.tcl`
consumes this to set `TCLLIBPATH` and to materialize a `RUNFILES_DIR` when only a manifest
is available; alternate wrappers can consume, ignore, or extend it as they see fit.
""",
    implementation = _tcl_toolchain_impl,
    attrs = {
        "tclcore": attr.label(
            doc = "A label to the `tclcore` files.",
        ),
        "tcllib": attr.label(
            doc = "A label to the `tcllib` files.",
        ),
        "tclsh": attr.label(
            doc = "The path to a `tclsh` binary. Runtime dependency of every produced `tcl_binary` / `tcl_test`.",
            cfg = "target",
            executable = True,
            mandatory = True,
        ),
        "wrapper_entrypoint": attr.label(
            doc = "Optional `.tcl` file added to the binary's runfiles and referenced via the `{entrypoint}` template substitution. The target's `default_runfiles` are also merged in. Leave unset when the wrapper doesn't need a bootstrap.",
            allow_single_file = True,
        ),
        "wrapper_template": attr.label(
            doc = "Template expanded per `tcl_binary` / `tcl_test`. The target's `default_runfiles` are merged into every produced binary, so a `filegroup` wrapping the template can list helper libraries under `data` (e.g. `@bazel_tools//tools/bash/runfiles`). See the wrapper template contract in the rule docs for the supported substitutions.",
            allow_single_file = True,
            mandatory = True,
        ),
    },
)
