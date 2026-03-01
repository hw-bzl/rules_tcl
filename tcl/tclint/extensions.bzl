"""Bzlmod extension for tclint toolchain."""

_BUILD_FILE_CONTENT = """\
load("@rules_tcl//tcl/tclint:tclint_toolchain.bzl", "TCLINT_TOOLCHAIN_TYPE", "tclint_toolchain")

tclint_toolchain(
    name = "tclint_toolchain",
    tclint = "@tcl_pip_deps//tclint",
    visibility = ["//visibility:public"],
)

toolchain(
    name = "toolchain",
    toolchain = ":tclint_toolchain",
    toolchain_type = TCLINT_TOOLCHAIN_TYPE,
    visibility = ["//visibility:public"],
)
"""

def _tclint_toolchains_repo_impl(repository_ctx):
    repository_ctx.file("BUILD.bazel", _BUILD_FILE_CONTENT)

_tclint_toolchains_repo = repository_rule(
    implementation = _tclint_toolchains_repo_impl,
)

_toolchain = tag_class(
    doc = "Configures the tclint toolchain.",
    attrs = {},
)

def _tclint_extension_impl(module_ctx):
    for mod in module_ctx.modules:
        for _ in mod.tags.toolchain:
            _tclint_toolchains_repo(
                name = "tclint_toolchains",
            )
            return

tclint = module_extension(
    implementation = _tclint_extension_impl,
    tag_classes = {
        "toolchain": _toolchain,
    },
)
