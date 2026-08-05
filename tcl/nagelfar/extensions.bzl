"""Bzlmod extension for Nagelfar.

Fetches one repository per known Nagelfar release and consolidates the
user-facing labels into a single `@nagelfar` hub repo:

    @nagelfar//:nagelfar   -> nagelfar.tcl from the newest release
    @nagelfar//:syntaxdb   -> shipped syntaxdb*.tcl from the newest release
    @nagelfar//135:nagelfar
    @nagelfar//135:syntaxdb

Consumers combine these labels with their own syntaxdb files and extra
arguments to declare a `nagelfar_toolchain(...)` in their own package,
then `register_toolchains(...)` it.
"""

load("@bazel_skylib//lib:versions.bzl", "versions")
load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")

NAGELFAR_VERSIONS = {
    "133": struct(
        urls = ["https://downloads.sourceforge.net/project/nagelfar/Rel_133/nagelfar133.tar.gz"],
        integrity = "sha256-gVxjUtp7iMP7PHJjrAIh/gqCKABX6fV6vfXzpWO6TkE=",
        strip_prefix = "nagelfar133",
    ),
    "135": struct(
        urls = ["https://downloads.sourceforge.net/project/nagelfar/Rel_135/nagelfar135.tar.gz"],
        integrity = "sha256-O6+SD7NLc+MgZxGDZdB02FkpjivON0itlFhiS+zoWyM=",
        strip_prefix = "nagelfar135",
    ),
}

_ARCHIVE_BUILD_FILE = """\
filegroup(
    name = "nagelfar",
    srcs = ["nagelfar.tcl"],
    visibility = ["//visibility:public"],
)

filegroup(
    name = "syntaxbuild",
    srcs = ["syntaxbuild.tcl"],
    visibility = ["//visibility:public"],
)

filegroup(
    name = "syntaxdb",
    srcs = glob(["syntaxdb*.tcl"]),
    visibility = ["//visibility:public"],
)
"""

_ALIAS_TEMPLATE = """\
alias(
    name = "{name}",
    actual = "@{target}//:{name}",
    visibility = ["//visibility:public"],
)
"""

_HUB_TARGETS = ("nagelfar", "syntaxbuild", "syntaxdb")

def _repo_name(version):
    return "nagelfar_" + version

def _hub_build_file(target):
    return "".join([
        _ALIAS_TEMPLATE.format(name = name, target = target)
        for name in _HUB_TARGETS
    ])

def _nagelfar_hub_impl(repository_ctx):
    repository_ctx.file(
        "BUILD.bazel",
        _hub_build_file(repository_ctx.attr.root_target),
    )
    for subpkg, target in repository_ctx.attr.subpackage_targets.items():
        repository_ctx.file(
            "{}/BUILD.bazel".format(subpkg),
            _hub_build_file(target),
        )

_nagelfar_hub = repository_rule(
    doc = """Creates the `@nagelfar` hub repository.

Emits top-level `nagelfar` / `syntaxdb` aliases pointing at the newest
version, and one subpackage per known release so callers can pin a
specific version via e.g. `@nagelfar//135:nagelfar`.
""",
    implementation = _nagelfar_hub_impl,
    attrs = {
        "root_target": attr.string(
            doc = "Archive repo name whose labels the top-level aliases point at.",
            mandatory = True,
        ),
        "subpackage_targets": attr.string_dict(
            doc = "Subpackage name -> archive repo name.",
            mandatory = True,
        ),
    },
)

def _nagelfar_extension_impl(module_ctx):
    sorted_versions = sorted(NAGELFAR_VERSIONS, key = versions.parse)
    latest = sorted_versions[-1]

    for version, info in NAGELFAR_VERSIONS.items():
        http_archive(
            name = _repo_name(version),
            urls = info.urls,
            integrity = info.integrity,
            strip_prefix = info.strip_prefix,
            build_file_content = _ARCHIVE_BUILD_FILE,
        )

    _nagelfar_hub(
        name = "nagelfar",
        root_target = _repo_name(latest),
        subpackage_targets = {v: _repo_name(v) for v in NAGELFAR_VERSIONS},
    )

    return module_ctx.extension_metadata(reproducible = True)

nagelfar = module_extension(
    doc = """Fetches the Nagelfar releases listed in `NAGELFAR_VERSIONS`.

Exposes them through a single `@nagelfar` hub repository. Consumers
reference Nagelfar via `@nagelfar//:nagelfar` (script, newest release),
`@nagelfar//:syntaxdb` (shipped syntax DBs, newest release), or the
per-version subpackages under `@nagelfar//<version>`.

Users declare their own `nagelfar_toolchain(...)` combining these
labels with any additional syntaxdb files and extra Nagelfar arguments,
then register it.
""",
    implementation = _nagelfar_extension_impl,
)
