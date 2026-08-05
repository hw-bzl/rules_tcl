# rules_tcl

Bazel rules for building, testing, and managing [Tcl](https://www.tcl-lang.org/) applications and libraries.

## Overview

`rules_tcl` provides a comprehensive set of Bazel rules for working with the Tcl scripting language. It supports:

- **Building executables** with `tcl_binary`
- **Creating reusable libraries** with `tcl_library`
- **Writing and running tests** with `tcl_test`
- **Code quality checks** with linting and formatting aspects
- **Dependency management** through Tcl's package system

The rules handle Tcl's package system, runfiles, and provide seamless integration with Bazel's build system.

## Quick Start

### Setup

`rules_tcl` does not ship a pre-registered toolchain — you declare the interpreter
and libraries you want and register a `tcl_toolchain` locally. Add the following to
your `MODULE.bazel`:

```python
bazel_dep(name = "rules_tcl", version = "{version}")
bazel_dep(name = "tcl_lang", version = "{tcl_lang_version}")
bazel_dep(name = "bazel_skylib", version = "{bazel_skylib_version}")

tcllib_ext = use_extension("@rules_tcl//tcl:extensions.bzl", "tcllib")
use_repo(tcllib_ext, "tcllib")

register_toolchains(
    "//toolchain",
)
```

Then in `//toolchain/BUILD.bazel`:

```python
load("@rules_tcl//tcl:tcl_toolchain.bzl", "tcl_toolchain", "tclcore_filegroup")

tclcore_filegroup(
    name = "tclcore",
    srcs = ["@tcl_lang//:tcl_core"],
)

tcl_toolchain(
    name = "tcl_toolchain",
    tclsh = "@tcl_lang//:tclsh",
    tclcore = ":tclcore",
    tcllib = "@tcllib",
    wrapper_template = "@rules_tcl//tcl/private:binary_wrapper.tpl",
    wrapper_entrypoint = "@rules_tcl//tcl/private:entrypoint.tcl",
)

toolchain(
    name = "toolchain",
    toolchain = ":tcl_toolchain",
    toolchain_type = "@rules_tcl//tcl:toolchain_type",
)
```

See [the `examples/` directory](https://github.com/hw-bzl/rules_tcl/tree/main/examples)
for a working setup. Users who need a custom interpreter (e.g. a vendor tool's
`tclsh`) or a custom wrapper stub swap the corresponding attribute — see the
[`tcl_toolchain`](./rules.md) rule doc for the full contract.

### Basic Example

Create a simple Tcl executable:

```python
load("@rules_tcl//tcl:tcl_binary.bzl", "tcl_binary")

tcl_binary(
    name = "hello",
    srcs = ["hello.tcl"],
)
```

### Library Example

Create a reusable Tcl library:

```python
load("@rules_tcl//tcl:tcl_library.bzl", "tcl_library")

tcl_library(
    name = "greetings",
    srcs = [
        "greet.tcl",
        "pkgIndex.tcl",  # Include to make the library available via `package require`
    ],
)
```

A `pkgIndex.tcl` is only needed when consumers will load the library with
`package require`. Libraries without one are still available to their
dependents through runfiles and can be loaded directly with `source`.
