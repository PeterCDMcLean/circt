# Shared helpers for the CIRCT Bazel overlay.
#
# This file deliberately contains no project-specific (Mojo/Modular/etc.)
# assumptions: it only knows about CIRCT's own source layout and about the
# `@llvm-project` Bazel overlay.
#
# Conventions used by every BUILD.bazel in this overlay:
#
#   * include paths: all CIRCT headers and TableGen outputs are reachable as
#     "circt/<...>", i.e. the `include/` directory is the include root. This is
#     implemented with `strip_include_prefix = "/include"`, which is
#     repository-root relative, so it keeps working no matter which directory
#     (or repository) CIRCT is checked out into.
#
#   * internal labels are repository-relative ("//include/...", "//lib/...")
#     and never spelled "@circt//...". That makes the same BUILD files work
#     when CIRCT is the main repository, a `local_repository`, or a Bazel
#     module.
#
#   * generated files are produced by `@llvm-project//mlir:tblgen.bzl`'s
#     `gentbl_cc_library`, using the `mlir-tblgen` binary from the consumer's
#     `@llvm-project`.

"""Shared helpers for the CIRCT Bazel overlay.

The rules here centralize the parts that would otherwise be copy-pasted into
every BUILD file: the `mlir-tblgen` binary, the MLIR TableGen inputs, and the
`circt/...` include layout.
"""

load("@llvm-project//mlir:tblgen.bzl", "gentbl_cc_library")
load("@rules_cc//cc:cc_library.bzl", "cc_library")

# The TableGen binary that drives every CIRCT `.td` file. `mlir-tblgen` is the
# only binary needed: CIRCT does not ship a custom TableGen backend.
MLIR_TBLGEN = "@llvm-project//mlir:mlir-tblgen"

# MLIR TableGen sources that CIRCT `.td` files include. Over-approximating this
# list is harmless: it only adds TableGen inputs and `-I` paths, and it keeps
# the per-package BUILD files free of per-file bookkeeping. Trim per dialect if
# you care about TableGen action granularity.
MLIR_TD_DEPS = [
    "@llvm-project//mlir:ArithOpsTdFiles",
    "@llvm-project//mlir:AttrTdFiles",
    "@llvm-project//mlir:BuiltinDialectTdFiles",
    "@llvm-project//mlir:CallInterfacesTdFiles",
    "@llvm-project//mlir:CastInterfacesTdFiles",
    "@llvm-project//mlir:ControlFlowInterfacesTdFiles",
    "@llvm-project//mlir:DataLayoutInterfacesTdFiles",
    "@llvm-project//mlir:FunctionInterfacesTdFiles",
    "@llvm-project//mlir:InferIntRangeInterfaceTdFiles",
    "@llvm-project//mlir:InferTypeOpInterfaceTdFiles",
    "@llvm-project//mlir:MemorySlotInterfacesTdFiles",
    "@llvm-project//mlir:OpBaseTdFiles",
    "@llvm-project//mlir:PassBaseTdFiles",
    "@llvm-project//mlir:SideEffectInterfacesTdFiles",
]

def circt_gentbl(name, td_file, tbl_outs, deps = [], **kwargs):
    """`gentbl_cc_library` with CIRCT's defaults.

    The generated files land in the same package as the `.td` file and are
    exposed under their "circt/..." path via `strip_include_prefix`.

    Args:
      name: target name (mirrors the CIRCT CMake TableGen target where one
        exists, e.g. `CIRCTHWAttrIncGen`).
      td_file: the `.td` file, relative to the current package.
      tbl_outs: {output file: [tblgen options]}, as for `gentbl_cc_library`.
      deps: additional `td_library` targets (MLIR td deps are added
        automatically).
      **kwargs: forwarded to `gentbl_cc_library`.
    """
    gentbl_cc_library(
        name = name,
        tblgen = MLIR_TBLGEN,
        td_file = td_file,
        tbl_outs = tbl_outs,
        deps = deps + MLIR_TD_DEPS,
        strip_include_prefix = "/include",
        **kwargs
    )

def circt_headers(name, srcs, deps = [], **kwargs):
    """A header-only CIRCT library with "circt/..." include paths.

    Args:
      name: target name (conventionally `headers`).
      srcs: headers, relative to the current package.
      deps: CIRCT/MLIR targets whose include paths and generated files are
        needed to use these headers.
      **kwargs: forwarded to `cc_library`.
    """
    cc_library(
        name = name,
        hdrs = srcs,
        strip_include_prefix = "/include",
        deps = deps,
        **kwargs
    )
