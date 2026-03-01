"""Tcl Bazel rules"""

load(":tcl_binary.bzl", _tcl_binary = "tcl_binary")
load(":tcl_library.bzl", _tcl_library = "tcl_library")
load(":tcl_toolchain.bzl", _tcl_toolchain = "tcl_toolchain")

tcl_binary = _tcl_binary
tcl_library = _tcl_library
tcl_toolchain = _tcl_toolchain
