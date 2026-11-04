# Building the overlay with a stub `@llvm-project`

`setup.sh` builds a throwaway Bazel workspace that consumes this overlay exactly
like a real consumer would, but with a *stub* `llvm-project` module so that
nothing needs to be compiled from LLVM sources:

* the stub ships the real MLIR/LLVM `.td` files (and, optionally, the real
  headers plus CMake-generated MLIR headers) so `mlir-tblgen` and the C++
  compiler see the same inputs as a real consumer;
* `@llvm-project//mlir:mlir-tblgen` is a wrapper around a prebuilt
  `mlir-tblgen` binary (from an existing CMake or Bazel LLVM build);
* the C++ library targets are header-only stubs, which is enough to compile
  every CIRCT translation unit but not to link a binary.

Usage:

```bash
bazel/validation/setup.sh \
    --llvm-src  /path/to/llvm-project \
    --llvm-build /path/to/llvm-build \
    --work /home/$USER/circt-bazel-check
```

`--llvm-build` must contain `bin/mlir-tblgen`, `include/`, and
`tools/mlir/include/` (the CMake build tree). Without it, only the `.td` files
are copied and the generated `mlir-tblgen` wrapper must be provided manually.

Then:

```bash
cd "$WORK"
bazel query 'kind("cc_library|cc_binary", @circt//...)'
bazel build --jobs=1 @circt//include/...   # runs every mlir-tblgen action
bazel build --jobs=1 @circt//lib/...       # compiles all covered libraries
```

The generated workspace is a validation artifact; it is not part of the
overlay and must not be committed.
