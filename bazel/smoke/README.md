# Smoke test

`smoke.cpp` builds a minimal `hw.module` with an `hw.constant` and a `comb.xor`
and prints it. It exercises the HW and Comb dialects end-to-end (TableGen
output, C++ libraries, include layout), so it is the cheapest check that the
overlay is wired correctly.

## With a real consumer workspace (supported path)

Assuming the consumer already provides `@llvm-project` (see
[`docs/bazel.md`](../../docs/bazel.md)), either as a sibling repository
(model A):

```python
# consumer MODULE.bazel
local_repository = use_repo_rule("@bazel_tools//tools/build_defs/repo:local.bzl", "local_repository")
local_repository(name = "circt", path = "third_party/circt")
```

or as a Bazel module (model B), then:

```bash
bazel build @circt//bazel/smoke:smoke --cxxopt=-std=c++20
bazel run   @circt//bazel/smoke:smoke --cxxopt=-std=c++20
```

Expected output (module printed, no ports):

```mlir
hw.module @top() {
  %c42_i32 = hw.constant 42 : i32
  %0 = comb.xor %c42_i32, %c42_i32 : i32
  hw.output
}
```

## Status of this rule

* The translation unit is known to compile against the overlay's generated
  headers and a real LLVM `6941494e2ae` MLIR (verified while preparing this
  branch, see `OVERLAY-STATUS.md`).
* Linking was **not** verified in this worktree: the overlay intentionally
  contains no MLIR/LLVM libraries, and the local LLVM CMake build's archives
  were incomplete (build in progress). Linking happens against your
  `@llvm-project`, so the command above is the one to run.

## Using the stub harness instead

`bazel/validation/setup.sh` creates a throwaway workspace whose
`@llvm-project` is a header/`.td`-only stub. In that workspace the smoke
target compiles but cannot link (the stub libraries are empty). That is
expected; use it for `bazel build` of the libraries, not for `bazel run`.
