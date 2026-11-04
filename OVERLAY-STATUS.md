# CIRCT Bazel overlay - status

Branch `bazel-overlay`, based on upstream CIRCT
`76eec00fe23f39e66a41894e266d0acfb886d925` (2026-11-02).

Goal: build a coherent CIRCT subset with Bazel on top of a consumer-provided
`@llvm-project` (LLVM/MLIR already built with Bazel). CMake remains the source
of truth for source lists and inter-library dependencies.

## Files added / changed

New files:

```
MODULE.bazel                                   module `circt`
bazel/BUILD.bazel                              package marker for circt.bzl
bazel/circt.bzl                                shared rules (tblgen defaults, headers)
bazel/smoke/{BUILD.bazel,smoke.cpp,README.md}  optional end-to-end smoke test
bazel/validation/{README.md,setup.sh}          validation harness (stub @llvm-project)
docs/bazel.md                                  integration + maintenance guide
OVERLAY-STATUS.md                              this file

include/circt/BUILD.bazel                          TableGen-only (Types.td)
include/circt/Support/BUILD.bazel
include/circt/Conversion/BUILD.bazel
include/circt/Dialect/{Emit,HW,Comb,Seq,SV,LTL,Debug,OM,Verif}/BUILD.bazel
include/circt/Dialect/Sim/BUILD.bazel              TableGen-only (Seq includes its .td)

lib/Support/BUILD.bazel
lib/Dialect/{Emit,HW,Comb,Seq,SV,LTL,Debug,OM,Verif}/BUILD.bazel
lib/Conversion/ExportVerilog/BUILD.bazel
lib/Conversion/SeqToSV/BUILD.bazel
```

Modified file (compatibility only, see `docs/bazel.md` §9):

```
include/circt/Support/LLVM.h     using llvm::MapVector -> using mlir::MapVector
```

No other upstream source, Mojo/HDL tree, or CMake file was touched. The main
CIRCT checkout and the running CMake/Bazel builds were not modified.

## Targets defined

212 Bazel targets in total (61 `cc_library`/`cc_binary`; the rest are
`gentbl` rules, generated filegroups and `td_library`s). The interesting ones:

| Bazel target | CMake equivalent |
| --- | --- |
| `//lib/Support:circt_support` | `CIRCTSupport` |
| `//lib/Dialect/Emit:circt_emit` | `CIRCTEmit` |
| `//lib/Dialect/HW:circt_hw` | `CIRCTHW` |
| `//lib/Dialect/Comb:circt_comb` | `CIRCTComb` |
| `//lib/Dialect/Seq:circt_seq` | `CIRCTSeq` |
| `//lib/Dialect/SV:circt_sv` | `CIRCTSV` |
| `//lib/Dialect/LTL:circt_ltl` | `CIRCTLTL` |
| `//lib/Dialect/Debug:circt_debug` | `CIRCTDebug` |
| `//lib/Dialect/OM:circt_om` | `CIRCTOM` |
| `//lib/Dialect/Verif:circt_verif` | `CIRCTVerif` |
| `//lib/Conversion/ExportVerilog:circt_export_verilog` | `CIRCTExportVerilog` |
| `//lib/Conversion/SeqToSV:circt_seq_to_sv` | `CIRCTSeqToSV` |
| `//bazel/smoke:smoke` | (new smoke test) |

Plus `:headers` targets and TableGen targets (`MLIRHWIncGen`,
`CIRCTHWAttrIncGen`, `CIRCTConversionPassIncGen`, ...) per include directory,
named after their CMake counterparts.

Out of scope (documented in `docs/bazel.md` §6): all other dialects (FIRRTL,
ESI, SMT/Z3, Calyx, Arc, ...), every `*/Transforms` and `*Reductions`, CaDiCaL,
Cap'n Proto, Python bindings, C API, tools and tests.

## Validation performed

Environment: 4 cores / 7 GB, `--jobs=1`. A long LLVM/CMake build was running
in the background; it was neither stopped nor restarted.

Validation used a throwaway consumer workspace with a **stub `@llvm-project`**
(`bazel/validation/setup.sh`). The stub carries the *real* MLIR/LLVM headers
and `.td` files from the local LLVM `6941494e2ae` checkout plus a prebuilt
`mlir-tblgen`. The C++ library targets of the stub are header-only, so CIRCT
compiles but nothing links. This avoids building LLVM from scratch.

1. **Target graph** - `bazel query '@circt//...'` and
   `bazel build --nobuild @circt//include/... @circt//lib/...`:
   212 targets load and analyze with no missing labels, cycles, or
   visibility errors.

2. **TableGen wiring, run by Bazel** - `bazel build @circt//include/...`:
   all **100 `mlir-tblgen` actions execute successfully** inside Bazel
   (`TdGenerate`), covering every `gentbl` target of the overlay. An
   independent cross-check script that invokes the same `mlir-tblgen` with the
   same flags outside Bazel also reports 100/100.

3. **C++ compile, run by Bazel** - final clean build:
   `bazel build --jobs=1 @circt//include/... @circt//lib/...
   --repo_env=CC=clang --repo_env=CXX=clang++ --cxxopt=-std=c++20` →
   **211 targets, 490 actions, success in 430 s**. All 13 libraries compile,
   including `ExportVerilog` (largest TU) and `SeqToSV`.

4. **Formatting** - `buildifier 8.2.1 -mode=check -lint=warn` on every
   `BUILD.bazel`, `MODULE.bazel` and `.bzl` file: clean.

5. **Smoke test** - `bazel/smoke/smoke.cpp` **compiles** against the overlay's
   Bazel-generated headers and the real MLIR headers
   (`clang++ -std=c++20 -fsyntax-only`, rc=0).

6. **Integration model A (sibling repository)** - validated in a separate
   scratch workspace (`/home/pmclean/circt-model-a-check`, not part of this
   branch): `local_repository(name = "circt", path = ...)` plus a
   *repository-rule generated* `@llvm-project` with no `MODULE.bazel` marker
   (i.e. exactly the case that cannot be expressed as a Bazel module).
   `bazel build --nobuild @circt//...` analyzes all **212 targets**;
   `@circt//lib/Dialect/HW:circt_hw` and `@circt//bazel/smoke:smoke` resolve.
   One requirement surfaced: the consumer's `MODULE.bazel` must declare
   `rules_cc` *and* `bazel_skylib` so that `@rules_cc//...` loads inside the
   CIRCT repo and `@bazel_skylib//...` inside the LLVM repo; documented in
   `docs/bazel.md` §2.

## Not validated, and why

* **Linking the smoke binary** was not run. The overlay deliberately contains
  no MLIR/LLVM libraries; linking must use the consumer's `@llvm-project`. The
  local LLVM CMake build is still in progress and its archives are incomplete
  (`libMLIRIR.a` is missing symbols), so an ad-hoc link here would be
  misleading. The command to run with a real consumer is:
  `bazel run @circt//bazel/smoke:smoke --cxxopt=-std=c++20`.
* **No LLVM/MLIR build from scratch** was attempted (CPU/disk constraints, and
  an LLVM CMake build was already running).
* The stub-harness validation compiles CIRCT against real MLIR *headers* but
  not against real MLIR *libraries*; ABI-level issues between the consumer's
  LLVM build and CIRCT would only surface in a real consumer workspace.
* Bazel 9.3.1 was used for early experimentation; final validation used
  **Bazel 8.4.2** (bzlmod). Bazel 7 was not tested.

## Exact next commands

For a consumer that already builds LLVM/MLIR with Bazel (model A, recommended):

```python
# consumer MODULE.bazel
local_repository = use_repo_rule("@bazel_tools//tools/build_defs/repo:local.bzl", "local_repository")
local_repository(name = "circt", path = "third_party/circt")
```

```bash
bazel query '@circt//lib/...'
bazel build --jobs=1 @circt//lib/...
bazel run @circt//bazel/smoke:smoke --cxxopt=-std=c++20   # prints hw.module
```

For model B (CIRCT as a module) see `docs/bazel.md` §3; the consumer must
provide `llvm-project-overlay` as a module (or override it), and cannot use an
extension-generated `@llvm-project`.

To reproduce the validation without touching your real workspace:

```bash
bazel/validation/setup.sh \
    --llvm-src  ~/circt/llvm \
    --llvm-build ~/circt/llvm/build \
    --work /home/$USER/circt-bazel-check
cd /home/$USER/circt-bazel-check
bazel build --jobs=1 @circt//include/... @circt//lib/... \
    --repo_env=CC=clang --repo_env=CXX=clang++ --cxxopt=-std=c++20
```

Remaining work (in rough priority order):

1. Link + run `//bazel/smoke:smoke` in a real consumer workspace.
2. Add `lib/Dialect/{HW,Comb,Seq,SV}/*/Transforms` (needs no new external deps).
3. Add `lib/Conversion/{CombToArith,HWToSV,CombToLLVM}` once the above exist.
4. Optional: `install`/`cc_shared_library` rules if a CIRCT SDK is needed.
