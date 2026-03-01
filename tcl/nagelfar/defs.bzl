"""Nagelfar Bazel rules"""

load(":nagelfar_toolchain.bzl", _nagelfar_toolchain = "nagelfar_toolchain")
load(":tcl_nagelfar_aspect.bzl", _tcl_nagelfar_aspect = "tcl_nagelfar_aspect")
load(":tcl_nagelfar_test.bzl", _tcl_nagelfar_test = "tcl_nagelfar_test")

nagelfar_toolchain = _nagelfar_toolchain
tcl_nagelfar_aspect = _tcl_nagelfar_aspect
tcl_nagelfar_test = _tcl_nagelfar_test
