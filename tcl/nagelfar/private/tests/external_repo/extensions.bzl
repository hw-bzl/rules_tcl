"""Test-only bzlmod extension.

Materializes an `@nagelfar_external_pkg` repo containing a Tcl source
file and a `tcl_library` wrapping it. The consumer target in this
package depends on that library across a repo boundary, exercising the
"external target contributes a syntaxdb" path in the nagelfar aspect.
"""

_TCL_FILE_CONTENT = """\
# Written by the `nagelfar_external_pkg` repository rule. Exists purely
# to give the nagelfar aspect an external `tcl_library` whose procs a
# main-repo consumer can call.

namespace eval external_pkg {
    proc hello {greeting} {
        return "external says: $greeting"
    }
}
"""

_BUILD_FILE_CONTENT = """\
load("@rules_tcl//tcl:tcl_library.bzl", "tcl_library")

tcl_library(
    name = "external_pkg",
    srcs = ["external_pkg.tcl"],
    visibility = ["//visibility:public"],
)
"""

def _external_pkg_repo_impl(repository_ctx):
    repository_ctx.file("external_pkg.tcl", _TCL_FILE_CONTENT)
    repository_ctx.file("BUILD.bazel", _BUILD_FILE_CONTENT)

_external_pkg_repo = repository_rule(
    implementation = _external_pkg_repo_impl,
)

def _nagelfar_external_pkg_impl(module_ctx):
    _external_pkg_repo(name = "nagelfar_external_pkg")
    return module_ctx.extension_metadata(reproducible = True)

nagelfar_external_pkg = module_extension(
    implementation = _nagelfar_external_pkg_impl,
)
