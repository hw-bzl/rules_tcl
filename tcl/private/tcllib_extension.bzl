"""Bzlmod extension for tcllib.

Fetches one repository per known tcllib release and consolidates all
user-facing aliases into a single `@tcllib` hub repo:

    @tcllib          -> newest tcllib overall
    @tcllib//:tcl_8  -> newest tcllib compatible with Tcl 8
    @tcllib//:tcl_9  -> newest tcllib compatible with Tcl 9
    @tcllib//2.0     -> tcllib 2.0
    @tcllib//1.21    -> tcllib 1.21

The per-version archive repositories are extension-private; consumers
reference them only through the aliases above.
"""

load("@bazel_skylib//lib:versions.bzl", "versions")
load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")

TCLLIB_VERSIONS = {
    "1.18": struct(
        urls = ["https://core.tcl-lang.org/tcllib/uv/tcllib-1.18.tar.xz"],
        integrity = "sha256-AxAzBo+NgQ5TUfge76JdO4k0C8nTU3Xm4zR3dG+mSdE=",
        strip_prefix = "tcllib-1.18",
        supports = ["8"],
    ),
    "1.19": struct(
        urls = ["https://core.tcl-lang.org/tcllib/uv/tcllib-1.19.tar.xz"],
        integrity = "sha256-Sk9zzIrKHWtiVxewrOYSBc3ap3aPX5oOFg3WKrtBd+8=",
        strip_prefix = "tcllib-1.19",
        supports = ["8"],
    ),
    "1.20": struct(
        urls = ["https://core.tcl-lang.org/tcllib/uv/tcllib-1.20.tar.xz"],
        integrity = "sha256-GZ6Ox+4mIg6EY7yE3VXESWX8jvTUrG5GhLKxwDsb1bk=",
        strip_prefix = "tcllib-1.20",
        supports = ["8"],
    ),
    "1.21": struct(
        urls = ["https://core.tcl-lang.org/tcllib/uv/tcllib-1.21.tar.xz"],
        integrity = "sha256-EMd0njD91gkiUZMOihqiibGTo7fxq/F/7h1PqJgUdi8=",
        strip_prefix = "tcllib-1.21",
        supports = ["8"],
    ),
    "2.0": struct(
        urls = ["https://core.tcl-lang.org/tcllib/uv/tcllib-2.0.tar.xz"],
        integrity = "sha256-ZCwsZ5yQF6tv3tAzJOTOm19Ckkc7YlIOgqrOu2PAziA=",
        strip_prefix = "tcllib-2.0",
        supports = ["8", "9"],
    ),
}

def _latest_for_tcl(sorted_versions, major):
    matches = [v for v in sorted_versions if major in TCLLIB_VERSIONS[v].supports]
    if not matches:
        fail("No tcllib version declares support for Tcl {}".format(major))
    return matches[-1]

def _repo_name(version):
    return "tcllib_" + version.replace(".", "_")

_ARCHIVE_BUILD_FILE = """\
load("@rules_tcl//tcl:tcl_toolchain.bzl", "tcllib_filegroup")

tcllib_filegroup(
    name = "tcllib",
    srcs = glob(["modules/**"], exclude = ["*.bazel"]),
    prefix = "{prefix}",
    version = "{version}",
    visibility = ["//visibility:public"],
)
"""

_ALIAS_TEMPLATE = """\
alias(
    name = "{name}",
    actual = "@{target}//:tcllib",
    visibility = ["//visibility:public"],
)
"""

def _tcllib_hub_impl(repository_ctx):
    repository_ctx.file(
        "BUILD.bazel",
        "".join([
            _ALIAS_TEMPLATE.format(name = name, target = target)
            for name, target in repository_ctx.attr.root_aliases.items()
        ]),
    )
    for name, target in repository_ctx.attr.subpackage_aliases.items():
        repository_ctx.file(
            "{}/BUILD.bazel".format(name),
            _ALIAS_TEMPLATE.format(name = name, target = target),
        )

_tcllib_hub = repository_rule(
    doc = """Creates the `@tcllib` hub repository.

Emits one top-level `alias()` per entry in `root_aliases` and one
subpackage per entry in `subpackage_aliases`, so users can reference
specific tcllib versions as e.g. `@tcllib//2.0`.
""",
    implementation = _tcllib_hub_impl,
    attrs = {
        "root_aliases": attr.string_dict(
            doc = "Top-level alias name -> archive repo name.",
            mandatory = True,
        ),
        "subpackage_aliases": attr.string_dict(
            doc = "Subpackage name -> archive repo name.",
            mandatory = True,
        ),
    },
)

def _tcllib_extension_impl(module_ctx):
    sorted_versions = sorted(TCLLIB_VERSIONS, key = versions.parse)
    latest = sorted_versions[-1]

    for version, info in TCLLIB_VERSIONS.items():
        http_archive(
            name = _repo_name(version),
            urls = info.urls,
            integrity = info.integrity,
            strip_prefix = info.strip_prefix,
            build_file_content = _ARCHIVE_BUILD_FILE.format(
                prefix = info.strip_prefix,
                version = version,
            ),
        )

    _tcllib_hub(
        name = "tcllib",
        root_aliases = {
            "tcl_8": _repo_name(_latest_for_tcl(sorted_versions, "8")),
            "tcl_9": _repo_name(_latest_for_tcl(sorted_versions, "9")),
            "tcllib": _repo_name(latest),
        },
        subpackage_aliases = {v: _repo_name(v) for v in TCLLIB_VERSIONS},
    )

    return module_ctx.extension_metadata(reproducible = True)

tcllib = module_extension(
    doc = """Fetches the tcllib releases listed in `TCLLIB_VERSIONS`.

Exposes them through a single `@tcllib` hub repository. Consumers
reference tcllib via `@tcllib` (newest overall), `@tcllib//:tcl_8` /
`@tcllib//:tcl_9` (newest supporting a given Tcl major), or
`@tcllib//<version>` (a specific release).
""",
    implementation = _tcllib_extension_impl,
)
