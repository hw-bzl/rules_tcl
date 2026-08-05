"""tcl_toolchain"""

load(
    "//tcl/private:providers.bzl",
    _TclcoreInfo = "TclCoreInfo",
    _TcllibInfo = "TclLibInfo",
)
load(
    "//tcl/private:tclcore_filegroup.bzl",
    _tclcore_filegroup = "tclcore_filegroup",
)
load(
    "//tcl/private:tcllib_filegroup.bzl",
    _tcllib_filegroup = "tcllib_filegroup",
)
load(
    "//tcl/private:toolchain.bzl",
    _TOOLCHAIN_TYPE = "TOOLCHAIN_TYPE",
    _tcl_toolchain = "tcl_toolchain",
)

tcl_toolchain = _tcl_toolchain
tclcore_filegroup = _tclcore_filegroup
tcllib_filegroup = _tcllib_filegroup
TclCoreInfo = _TclcoreInfo
TclLibInfo = _TcllibInfo
TOOLCHAIN_TYPE = _TOOLCHAIN_TYPE
