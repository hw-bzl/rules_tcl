"""Bzlmod extension for Nagelfar toolchain."""

_NAGELFAR_URL = "https://sourceforge.net/projects/nagelfar/files/Rel_135/nagelfar135.tar.gz"
_NAGELFAR_SHA256 = ""
_NAGELFAR_STRIP_PREFIX = "nagelfar135"

_BUILD_FILE_CONTENT = """\
load("@rules_tcl//tcl/nagelfar:nagelfar_toolchain.bzl", "NAGELFAR_TOOLCHAIN_TYPE", "nagelfar_toolchain")

filegroup(
    name = "nagelfar_tcl",
    srcs = ["nagelfar.tcl"],
    visibility = ["//visibility:public"],
)

filegroup(
    name = "syntaxdb",
    srcs = glob(["syntaxdb*.tcl"]),
    visibility = ["//visibility:public"],
)

nagelfar_toolchain(
    name = "nagelfar_toolchain",
    nagelfar = ":nagelfar_tcl",
    syntaxdb = ":syntaxdb",
    visibility = ["//visibility:public"],
)

toolchain(
    name = "toolchain",
    toolchain = ":nagelfar_toolchain",
    toolchain_type = NAGELFAR_TOOLCHAIN_TYPE,
    visibility = ["//visibility:public"],
)
"""

def _nagelfar_toolchains_repo_impl(repository_ctx):
    repository_ctx.download_and_extract(
        url = _NAGELFAR_URL,
        sha256 = _NAGELFAR_SHA256,
        stripPrefix = _NAGELFAR_STRIP_PREFIX,
    )

    repository_ctx.file("BUILD.bazel", _BUILD_FILE_CONTENT)

_nagelfar_toolchains_repo = repository_rule(
    implementation = _nagelfar_toolchains_repo_impl,
)

_toolchain = tag_class(
    doc = "Configures the Nagelfar toolchain.",
    attrs = {},
)

def _nagelfar_extension_impl(module_ctx):
    for mod in module_ctx.modules:
        for _ in mod.tags.toolchain:
            _nagelfar_toolchains_repo(
                name = "nagelfar_toolchains",
            )
            return

nagelfar = module_extension(
    implementation = _nagelfar_extension_impl,
    tag_classes = {
        "toolchain": _toolchain,
    },
)
