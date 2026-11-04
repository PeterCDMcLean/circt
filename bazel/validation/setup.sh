#!/usr/bin/env bash
# Create a throwaway Bazel workspace that consumes the CIRCT overlay together
# with a *stub* @llvm-project (real MLIR headers/.td files, no LLVM compile).
#
# Usage:
#   setup.sh --llvm-src <llvm-project-dir> --llvm-build <llvm-build-dir> --work <dir>
#
# --llvm-build must contain bin/mlir-tblgen, include/ and tools/mlir/include/.
set -euo pipefail

LLVM_SRC=""
LLVM_BUILD=""
WORK=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --llvm-src) LLVM_SRC=$2; shift 2 ;;
    --llvm-build) LLVM_BUILD=$2; shift 2 ;;
    --work) WORK=$2; shift 2 ;;
    -h|--help) sed -n '2,10p' "$0"; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 1 ;;
  esac
done

[[ -n "$LLVM_SRC" && -n "$LLVM_BUILD" && -n "$WORK" ]] || {
  echo "usage: $0 --llvm-src <dir> --llvm-build <dir> --work <dir>" >&2
  exit 1
}

OVERLAY=$(cd "$(dirname "$0")/../.." && pwd)
STUB="$WORK/stub-llvm"
mkdir -p "$WORK" "$STUB/mlir/include" "$STUB/mlir/gen" "$STUB/llvm/include" "$STUB/llvm/gen"

echo "Copying MLIR/LLVM TableGen and header trees..." >&2
cp -r "$LLVM_SRC/mlir/include/." "$STUB/mlir/include/"
cp -r "$LLVM_BUILD/tools/mlir/include/." "$STUB/mlir/gen/"
cp -r "$LLVM_SRC/llvm/include/." "$STUB/llvm/include/"
cp -r "$LLVM_BUILD/include/." "$STUB/llvm/gen/"

cat > "$STUB/MODULE.bazel" <<'EOF'
module(name = "llvm-project-overlay", version = "0.0.0")
bazel_dep(name = "rules_cc", version = "0.2.25")
bazel_dep(name = "bazel_skylib", version = "1.9.0")
EOF

# The tblgen shim points at the prebuilt binary.
cat > "$STUB/mlir/mlir-tblgen.sh" <<EOF
#!/bin/sh
exec "$LLVM_BUILD/bin/mlir-tblgen" "\$@"
EOF
chmod +x "$STUB/mlir/mlir-tblgen.sh"

cp "$LLVM_SRC/utils/bazel/llvm-project-overlay/mlir/tblgen.bzl" "$STUB/mlir/tblgen.bzl"

cat > "$STUB/mlir/BUILD.bazel" <<'EOF'
load("@rules_cc//cc:cc_library.bzl", "cc_library")
load(":tblgen.bzl", "td_library")

package(default_visibility = ["//visibility:public"])

# Stub LLVM Bazel overlay: every td_library name used by CIRCT maps to all
# MLIR .td files (over-approximation is fine for validation).
_TDS = ["ArithOpsTdFiles","AttrTdFiles","BuiltinDialectTdFiles","CallInterfacesTdFiles",
        "CastInterfacesTdFiles","ControlFlowInterfacesTdFiles","DataLayoutInterfacesTdFiles",
        "FunctionInterfacesTdFiles","InferIntRangeInterfaceTdFiles","InferTypeOpInterfaceTdFiles",
        "MemorySlotInterfacesTdFiles","OpBaseTdFiles","PassBaseTdFiles","SideEffectInterfacesTdFiles"]
[td_library(name = n, srcs = glob(["include/**/*.td"]), includes = ["include"]) for n in _TDS]

cc_library(
    name = "headers",
    hdrs = glob(["include/**", "gen/**"]),
    includes = ["include", "gen"],
    deps = ["//llvm:headers"],
)

_LIBS = ["IR","Pass","Support","Transforms","TransformUtils","ArithDialect","CallInterfaces",
         "SideEffectInterfaces","InferTypeOpInterface","InferIntRangeInterface","InferIntRangeCommon",
         "MemorySlotInterfaces","ControlFlowInterfaces","FunctionInterfaces","DataLayoutInterfaces",
         "FuncDialect","Dialect","Analysis"]
[cc_library(name = n, deps = [":headers"]) for n in _LIBS]

sh_binary(name = "mlir-tblgen", srcs = ["mlir-tblgen.sh"])
EOF

cat > "$STUB/llvm/BUILD.bazel" <<'EOF'
load("@rules_cc//cc:cc_library.bzl", "cc_library")

package(default_visibility = ["//visibility:public"])

cc_library(
    name = "headers",
    hdrs = glob(["include/**", "gen/**"]),
    includes = ["include", "gen"],
)

cc_library(name = "Support", deps = [":headers"])
cc_library(name = "Core", deps = [":headers"])
EOF

cat > "$WORK/MODULE.bazel" <<EOF
module(name = "circt_check")
bazel_dep(name = "rules_cc", version = "0.2.25")
bazel_dep(name = "bazel_skylib", version = "1.9.0")
bazel_dep(name = "circt", version = "0.1.0")
local_path_override(module_name = "circt", path = "$OVERLAY")
bazel_dep(name = "llvm-project-overlay", version = "0.0.0", repo_name = "llvm-project")
local_path_override(module_name = "llvm-project-overlay", path = "stub-llvm")
EOF

echo "8.4.2" > "$WORK/.bazelversion"

echo "Workspace ready in $WORK" >&2
echo "Next: cd $WORK && bazel build --jobs=1 @circt//include/... @circt//lib/..." >&2
