# Vendored CIRCT (hw + comb)

This directory contains the CIRCT sources needed to build real `hw`/`comb` ops
inside the Mojo compiler. It is a *vendored subset*, not a full CIRCT checkout.

* Source: `~/circt` at `76eec00fe23f39e66a41894e266d0acfb886d925` (2026-11-02).
* LLVM: built against Mojo's pinned `@llvm-project` (`6941494e`), not CIRCT's
  own submodule pin. This is what makes the ops share Mojo's MLIR context and
  type-ID universe.
* Local patch applied before vendoring:
  `include/circt/Support/LLVM.h` imports `mlir::MapVector` instead of
  `llvm::MapVector` (the alias was added to MLIR in `145af0deae5`). Without it,
  two CIRCT TUs fail with an ambiguous `MapVector`.
* Copied:
  * `include/circt/` (all headers and `.td` files, 230 `.td`),
  * `lib/Support/*.cpp,*.h`,
  * `lib/Dialect/HW/*.cpp,*.h` (excluding `HWReductions.cpp`, which needs
    `circt/Reduce`),
  * `lib/Dialect/Comb/*.cpp,*.h`.
* Not copied: all other dialects, transforms, reductions, `ExportVerilog`,
  tools, tests.

`BUILD.bazel` generates the TableGen outputs with the LLVM Bazel overlay
(`@llvm-project//mlir:tblgen.bzl`) and exposes `:circt_comb` (which pulls in
`:circt_hw` and `:circt_support`).

Refresh procedure (after a CIRCT bump):

```bash
# 1. Apply/adjust the MapVector import in ~/circt if still needed.
# 2. Re-run the copy (keeps the local BUILD.bazel):
third_party/circt/refresh.sh
# 3. Add/remove TableGen targets in BUILD.bazel if CIRCT's CMakeLists changed.
./bazelw build //third_party/circt:circt_comb
```
