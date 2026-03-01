"""Tclint Bazel rules"""

load(":tcl_tclint_aspect.bzl", _tcl_tclint_aspect = "tcl_tclint_aspect")
load(":tcl_tclint_fmt_aspect.bzl", _tcl_tclint_fmt_aspect = "tcl_tclint_fmt_aspect")
load(":tcl_tclint_fmt_test.bzl", _tcl_tclint_fmt_test = "tcl_tclint_fmt_test")
load(":tcl_tclint_test.bzl", _tcl_tclint_test = "tcl_tclint_test")
load(":tclint_toolchain.bzl", _tclint_toolchain = "tclint_toolchain")

tcl_tclint_fmt_aspect = _tcl_tclint_fmt_aspect
tcl_tclint_fmt_test = _tcl_tclint_fmt_test
tcl_tclint_aspect = _tcl_tclint_aspect
tcl_tclint_test = _tcl_tclint_test
tclint_toolchain = _tclint_toolchain
