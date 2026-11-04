# Building CIRCT with Bazel

CIRCT upstream only ships CMake. This directory contains a Bazel overlay: BUILD
files and TableGen wiring that build a coherent subset of CIRCT **on top of an
existing Bazel build of LLVM/MLIR**. The overlay does not vendor or build LLVM.

* CIRCT base revision: `76eec00fe23f39e66a41894e266d0acfb886d925` (2026-11-02).
* LLVM/MLIR is whatever the consumer provides as `@llvm-project`; the overlay
  was validated against LLVM `6941494e2ae` (LLVM 24.0.0git) using the Bazel
  overlay in `llvm-project/utils/bazel`.
* Bazel: validated with Bazel 8.4.2 (bzlmod). `bazel_dep`s come from BCR.

The overlay is project agnostic: no Mojo/Modular (or any other consumer)
assumptions, paths, or labels.

## 1. Requirements

### 1.1 Repository `@llvm-project`

The BUILD files only ever refer to LLVM/MLIR as `@llvm-project//...`. The
consumer must provide a repository with that *apparent name*. The following
targets are required:

C++ libraries:

| Target | Needed by |
| --- | --- |
| `@llvm-project//llvm:Support` | all of CIRCT |
| `@llvm-project//llvm:Core` | `ExportVerilog`, `SeqToSV` |
| `@llvm-project//mlir:IR` | all of CIRCT |
| `@llvm-project//mlir:Support` | all of CIRCT |
| `@llvm-project//mlir:Pass` | passes, `Seq`, `SV`, `ExportVerilog` |
| `@llvm-project//mlir:Transforms` | `Support`, `Emit`, `Seq`, `Verif`, `ExportVerilog` |
| `@llvm-project//mlir:TransformUtils` | `Support` |
| `@llvm-project//mlir:ArithDialect` | `Seq` |
| `@llvm-project//mlir:CallInterfaces` | `SV` |
| `@llvm-project//mlir:ControlFlowInterfaces` | `hw` TableGen |
| `@llvm-project//mlir:DataLayoutInterfaces` | `hw` TableGen |
| `@llvm-project//mlir:FunctionInterfaces` | `hw` TableGen |
| `@llvm-project//mlir:InferIntRangeCommon` | `HW` |
| `@llvm-project//mlir:InferIntRangeInterface` | `HW`, `Comb` |
| `@llvm-project//mlir:InferTypeOpInterface` | `HW`, `Comb`, `LTL`, `Debug` |
| `@llvm-project//mlir:MemorySlotInterfaces` | `HW` |
| `@llvm-project//mlir:SideEffectInterfaces` | `Debug`, `ExportVerilog` |

Bazel binaries and TableGen inputs:

| Target | Purpose |
| --- | --- |
| `@llvm-project//mlir:mlir-tblgen` | every `.td` file in the overlay |
| `@llvm-project//mlir:OpBaseTdFiles`, `BuiltinDialectTdFiles`, `AttrTdFiles` | core `.td` includes |
| `@llvm-project//mlir:{Call,Cast,ControlFlow,DataLayout,Function,SideEffect}InterfacesTdFiles` | dialect interfaces |
| `@llvm-project//mlir:{InferIntRange,InferTypeOp,MemorySlot}*TdFiles` | dialect interfaces |
| `@llvm-project//mlir:{ArithOps,PassBase}TdFiles` | pass/attribute definitions |
| `@llvm-project//mlir:tblgen.bzl` | `gentbl_cc_library`, `td_library` |

The exact list is `MLIR_TD_DEPS` in `bazel/circt.bzl`; add there if a new
dialect needs more MLIR `.td` files (a missing input shows up as
"could not find include file 'mlir/...'" from `mlir-tblgen`).

`cc_library` is loaded from `@rules_cc//cc:cc_library.bzl`, which is required
from Bazel 8 onwards.

### 1.2 LLVM revision

Minimum **LLVM `145af0deae5`**, which introduced `mlir::MapVector` (see
§9). The overlay does not pin an LLVM revision: that is the consumer's choice.
Because CIRCT tracks LLVM `main`, newer LLVM revisions may rename MLIR
libraries or `.td` files; see §10 for the refresh procedure.

## 2. Integration model A: sibling repository (recommended)

This is the simplest model, and the **only** one that works when
`@llvm-project` is produced by a repository rule or module extension in the
consumer's module (as is common: LLVM sources + local patches are usually
materialized by an extension, not taken from a registry).

Check CIRCT out as a submodule/subdirectory of the consumer repository and
declare it as a repository in the consumer's `MODULE.bazel`:

```python
# consumer MODULE.bazel
bazel_dep(name = "rules_cc", version = "0.2.25")
bazel_dep(name = "bazel_skylib", version = "1.9.0")

local_repository = use_repo_rule(
    "@bazel_tools//tools/build_defs/repo:local.bzl",
    "local_repository",
)

# third_party/circt is a git submodule of this repository.
local_repository(name = "circt", path = "third_party/circt")
```

The `rules_cc`/`bazel_skylib` deps are what make `@rules_cc//...` (loaded by
the CIRCT BUILD files) and `@bazel_skylib//...` (loaded by LLVM's
`mlir/tblgen.bzl`) visible from inside those repositories. Without them,
loading `@circt//...` fails with
`No repository visible as '@rules_cc' from repository '...circt'` or
`No repository visible as '@bazel_skylib' from repository '...llvm-project'`.

Then depend on CIRCT targets from anywhere in the consumer's tree:

```python
# consumer BUILD file
cc_library(
    name = "hdl_helpers",
    srcs = ["hdl_helpers.cc"],
    deps = [
        "@circt//lib/Dialect/HW:circt_hw",
        "@circt//lib/Dialect/Comb:circt_comb",
    ],
)
```

`@llvm-project` inside the CIRCT BUILD files resolves through the **consumer's**
repository mapping, so this model works with a generated `@llvm-project`
repository:

```python
# consumer MODULE.bazel, e.g. LLVM sources + patches generated by an extension
llvm = use_extension("//bazel:llvm.bzl", "llvm")
use_repo(llvm, "llvm-project")
```

The directory used by `local_repository` must look like a repository; CIRCT's
`MODULE.bazel` serves as that marker. `--override_repository=circt=/path` also
works (e.g. for developer checkouts) instead of editing `MODULE.bazel`.

Trade-offs:

* `@circt//...` labels are used at the consumer's call sites; the CIRCT tree
  itself only uses repository-relative labels (`//lib/...`), so it does not
  care where it lives.
* No version of CIRCT's dependency graph is evaluated, so this works even if
  the LLVM repo cannot be exposed as a Bazel module.
* In exchange, the consumer must ensure the CIRCT tree's own `MODULE.bazel`
  dependencies (currently `rules_cc`, `bazel_skylib`,
  `llvm-project-overlay`) are irrelevant/overridden - they are not used in
  this model.

Model A does **not** work by dropping the CIRCT BUILD files into an arbitrary
subdirectory of the consumer's *main* module (without a repository boundary):
the overlay's internal labels are repository-relative, so CIRCT must be its
own repository. This is deliberate: it keeps the BUILD files valid in both
models and in a standalone CIRCT checkout.

## 3. Integration model B: external Bazel module

CIRCT can also be a regular `bazel_dep`:

```python
# consumer MODULE.bazel
bazel_dep(name = "circt", version = "0.1.0")
local_path_override(module_name = "circt", path = "third_party/circt")

# LLVM/MLIR, provided by the consumer as a module.
bazel_dep(name = "llvm-project-overlay", version = "0.0.0")
local_path_override(
    module_name = "llvm-project-overlay",
    path = "third_party/llvm-project/utils/bazel",
)
```

Notes and caveats:

* Upstream LLVM's Bazel module is called `llvm-project-overlay` and maps its
  repository to `llvm-project` (`bazel_dep(..., repo_name = "llvm-project")`).
  `circt`'s `MODULE.bazel` already does that mapping, so only the module
  override is needed at the consumer.
* CIRCT declares `bazel_dep(name = "llvm-project-overlay", version = "0.0.0")`
  as a placeholder. If the consumer does not override it, module resolution
  fails with "module not found in registry". This is intentional: the overlay
  cannot choose an LLVM revision.
* **Repo-mapping caveat:** a repository generated by a module extension of the
  *consumer's* module is not visible to the `circt` module's packages. So if
  your LLVM is extension-generated (sources + patches), model B does not work,
  regardless of `--override_repository=llvm-project=...` (that flag applies to
  the main module's mapping). Use model A, or expose LLVM as a real module.
* Likewise, CIRCT's own repo name inside the external module is `circt`, but
  the overlay never uses `@circt//...` internally.

### 3.1 Consumers that still use WORKSPACE (bzlmod disabled)

The overlay's BUILD files are plain BUILD files; they work under
`--noenable_bzlmod` as long as `@llvm-project` and `@rules_cc` resolve inside
the `@circt` repository. Declare the repositories in order and add a
`repo_mapping` for `circt`:

```python
# consumer WORKSPACE
load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")

# rules_cc must be available before circt's BUILD files are loaded.
http_archive(name = "rules_cc", url = "...", sha256 = "...")
http_archive(name = "bazel_skylib", url = "...", sha256 = "...")

# The consumer's LLVM/MLIR (however it is materialized).
local_repository(name = "llvm-project", path = "third_party/llvm-project")

local_repository(
    name = "circt",
    path = "third_party/circt",
    repo_mapping = {
        "@llvm-project": "@llvm-project",
        "@rules_cc": "@rules_cc",
        "@bazel_skylib": "@bazel_skylib",
    },
)
```

Bazel >= 8 is recommended; bzlmod (models A/B above) is the tested
configuration.

## 4. Layout and conventions

```
MODULE.bazel                     module `circt`; declares the LLVM mapping
bazel/circt.bzl                  shared rules (tblgen defaults, header libs)
bazel/BUILD.bazel                package marker for circt.bzl
include/circt/**/BUILD.bazel     TableGen + header rules, one per include dir
lib/**/BUILD.bazel               cc_library per CMake library
bazel/smoke/                     optional end-to-end smoke test
bazel/validation/                script used to validate the overlay
docs/bazel.md                    this document
```

Conventions that keep the overlay maintainable:

* **One BUILD file per upstream directory**, named after the directory, so a
  future dialect or transform does not get swallowed by a root package.
* **Headers keep their `circt/...` include path** via
  `strip_include_prefix = "/include"`. This is repository-root relative, so it
  works regardless of checkout location or Bazel repo name.
* **Internal labels are repository-relative** (`//lib/Dialect/HW:circt_hw`),
  never `@circt//...`. Only `@llvm-project//...` is ever spelled with a repo.
* TableGen outputs are produced by `@llvm-project//mlir:tblgen.bzl`'s
  `gentbl_cc_library`; target names mirror the CMake TableGen targets
  (`CIRCTHWAttrIncGen`, `MLIRSVIncGen`, ...) to make refreshes mechanical.
* `td_library` rules own the `.td` files of their directory and nothing else;
  the **transitive textual** `.td` includes are listed in a per-package
  `TD_DEPS` list used by the `gentbl` rules. This avoids cycles in the target
  graph, which occur because some dialects include each other textually
  (`seq` <-> `sim`).

## 5. Covered libraries and targets

| Bazel target | CMake target | Directory |
| --- | --- | --- |
| `//lib/Support:circt_support` | `CIRCTSupport` | `lib/Support` |
| `//lib/Dialect/Emit:circt_emit` | `CIRCTEmit` | `lib/Dialect/Emit` |
| `//lib/Dialect/HW:circt_hw` | `CIRCTHW` | `lib/Dialect/HW` |
| `//lib/Dialect/Comb:circt_comb` | `CIRCTComb` | `lib/Dialect/Comb` |
| `//lib/Dialect/Seq:circt_seq` | `CIRCTSeq` | `lib/Dialect/Seq` |
| `//lib/Dialect/SV:circt_sv` | `CIRCTSV` | `lib/Dialect/SV` |
| `//lib/Dialect/LTL:circt_ltl` | `CIRCTLTL` | `lib/Dialect/LTL` |
| `//lib/Dialect/Debug:circt_debug` | `CIRCTDebug` | `lib/Dialect/Debug` |
| `//lib/Dialect/OM:circt_om` | `CIRCTOM` | `lib/Dialect/OM` |
| `//lib/Dialect/Verif:circt_verif` | `CIRCTVerif` | `lib/Dialect/Verif` |
| `//lib/Conversion/ExportVerilog:circt_export_verilog` | `CIRCTExportVerilog` | `lib/Conversion/ExportVerilog` |
| `//lib/Conversion/SeqToSV:circt_seq_to_sv` | `CIRCTSeqToSV` | `lib/Conversion/SeqToSV` |

`Emit`, `LTL`, `Debug`, `OM` and `Verif` are pulled in because `HW`, `SV` and
`ExportVerilog` link against them; they are small and have no optional
dependencies.

Per include directory there is also a `:headers` target (header-only, adds the
`circt/...` include path) and one `gentbl` target per upstream TableGen target:

```
//include/circt/Support:headers
//include/circt/Dialect/HW:headers
//include/circt/Dialect/HW:MLIRHWIncGen              # add_circt_dialect(HW hw)
//include/circt/Dialect/HW:CIRCTHWAttrIncGen         # HWAttributes.{h,cpp}.inc
//include/circt/Dialect/HW:CIRCTHWEnumsIncGen        # HWEnums.{h,cpp}.inc
//include/circt/Dialect/HW:CIRCTHWCanonicalizationIncGen
//include/circt/Dialect/HW:CIRCTHWOpInterfacesIncGen
//include/circt/Dialect/HW:CIRCTHWTypeInterfacesIncGen
//include/circt/Dialect/HW:CIRCTHWTransformsIncGen   # Passes.h.inc
//include/circt/Conversion:CIRCTConversionPassIncGen # Conversion/Passes.h.inc
...
```

Include the `circt/Conversion/Passes.h` umbrella header with care: see
§6.

## 6. Not covered

Deliberately out of scope (no BUILD rules; not built):

* **Dialects**: FIRRTL, Arc, AXI4, Calyx, DC, ESI, FSM, Handshake, HWArith,
  Interop, Kanagawa, LLHD, LoopSchedule, Moore, MSFT, Pipeline, PIR, Probe,
  RTG, RTGTest, Sim, SSP, SystemC, Synth, and `circt/Dialect/*/Transforms`.
  (`Sim` has a TableGen-only package because `Seq`'s `.td` files include
  `SimTypes.td`.)
* **Transforms/reductions**: `lib/Reduce`, every `*/Transforms` directory,
  `*Reductions.cpp` (`HWReductions`, `EmitReductions`, `OMReductions`, ...).
* **Optional dependencies**: CaDiCaL/SAT (`CIRCT_CADICAL_ENABLED`), Z3/SMT
  (`SMTToZ3LLVM`, `VerifToSMT`, `Verif` transforms), Cap'n Proto/ESI, Python
  bindings and the C API.
* **Tools, tests, docs**: `tools/`, `unittests/`, `test/`, `llvm-lit`
  integration; there are no `cc_binary` rules for `circt-opt`, `firtool`,
  etc.

Consequences:

* `lib/Support/SATSolver.cpp` is built in its "no solver available" mode
  (`#ifdef CIRCT_CADICAL_ENABLED` is not defined), which is the upstream
  fallback.
* `circt/Conversion/Passes.h` (the umbrella header) includes the headers of all
  conversions, including the dialects above. It is therefore not usable from
  Bazel. Include the per-conversion header instead, e.g.
  `circt/Conversion/SeqToSV.h`. The generated `Passes.h.inc` (pass
  declarations for all conversions) *is* built, because the covered
  conversions include it; it only contains declarations.

## 7. Adding a dialect or library

The recipe is mechanical; use `HW` and `Comb` as the reference. For a new
dialect `Foo` (`include/circt/Dialect/Foo`, `lib/Dialect/Foo`):

1. **TableGen + headers** - create `include/circt/Dialect/Foo/BUILD.bazel`:

   ```python
   load("@llvm-project//mlir:tblgen.bzl", "td_library")
   load("//bazel:circt.bzl", "circt_gentbl", "circt_headers")

   package(default_visibility = ["//visibility:public"])

   td_library(
       name = "td_files",
       srcs = glob(["*.td"]),
       includes = ["/include"],
   )

   # Transitive CIRCT `.td` packages textually included by this package's
   # files (see the TD_DEPS comment in the HW/Comb BUILD files).
   TD_DEPS = [
       ":td_files",
       "//include/circt/Dialect/HW:td_files",
       "//include/circt/Support:td_files",
   ]

   # For `add_circt_dialect(Foo foo)` / `add_mlir_dialect(Foo foo)`.
   circt_gentbl(
       name = "MLIRFooIncGen",
       td_file = "Foo.td",
       tbl_outs = {
           "Foo.h.inc": ["-gen-op-decls"],
           "Foo.cpp.inc": ["-gen-op-defs"],
           "FooTypes.h.inc": ["-gen-typedef-decls", "-typedefs-dialect=foo"],
           "FooTypes.cpp.inc": ["-gen-typedef-defs", "-typedefs-dialect=foo"],
           "FooDialect.h.inc": ["-gen-dialect-decls", "-dialect=foo"],
           "FooDialect.cpp.inc": ["-gen-dialect-defs", "-dialect=foo"],
       },
       deps = TD_DEPS,
   )

   circt_gentbl(
       name = "CIRCTFooEnumsIncGen",
       td_file = "Foo.td",
       tbl_outs = {
           "FooEnums.h.inc": ["-gen-enum-decls"],
           "FooEnums.cpp.inc": ["-gen-enum-defs"],
       },
       deps = TD_DEPS,
   )

   circt_headers(
       name = "headers",
       srcs = glob(["*.h"]),
       deps = [
           ":CIRCTFooEnumsIncGen",
           ":MLIRFooIncGen",
           "//include/circt/Support:headers",
           "@llvm-project//mlir:IR",
       ],
   )
   ```

   Copy each `mlir_tablegen(...)` line from the upstream
   `include/circt/Dialect/Foo/CMakeLists.txt` into a `tbl_outs` entry, keeping
   the exact flags (`-gen-attrdef-*`, `-attrdefs-dialect=foo`,
   `-gen-rewriters`, `...`). `add_circt_dialect`/`add_mlir_dialect` always
   produce the six files above; `add_circt_interface`/`add_mlir_interface`
   targets come in pairs
   (`-gen-op-interface-decls` / `-defs`, `-gen-type-interface-decls` /
   `-defs`).

2. **Library** - create `lib/Dialect/Foo/BUILD.bazel` mirroring
   `lib/Dialect/Foo/CMakeLists.txt`:

   ```python
   load("@rules_cc//cc:cc_library.bzl", "cc_library")

   package(default_visibility = ["//visibility:public"])

   cc_library(
       name = "circt_foo",
       srcs = [
           # exactly the source list of add_circt_dialect_library(CIRCTFoo ...)
       ],
       deps = [
           "//include/circt/Dialect/Foo:headers",
           "//lib/Support:circt_support",
           "@llvm-project//mlir:IR",
           "@llvm-project//mlir:Support",
       ],
   )
   ```

   Translate `LINK_LIBS PUBLIC` one by one, and `LINK_COMPONENTS` to
   `@llvm-project//llvm:<component>`:

   | CMake | Bazel |
   | --- | --- |
   | `CIRCTSupport`, `CIRCTHW`, ... | `//lib/Support:circt_support`, `//lib/Dialect/HW:circt_hw`, ... |
   | `MLIRIR` | `@llvm-project//mlir:IR` |
   | `MLIRSupport` | `@llvm-project//mlir:Support` |
   | `MLIRPass` | `@llvm-project//mlir:Pass` |
   | `MLIRTransforms` | `@llvm-project//mlir:Transforms` |
   | `MLIRTransformUtils` | `@llvm-project//mlir:TransformUtils` |
   | `MLIRArithDialect` | `@llvm-project//mlir:ArithDialect` |
   | `MLIRFuncDialect` | `@llvm-project//mlir:FuncDialect` |
   | `MLIRCallInterfaces` | `@llvm-project//mlir:CallInterfaces` |
   | `MLIRSideEffectInterfaces` | `@llvm-project//mlir:SideEffectInterfaces` |
   | `MLIRInferTypeOpInterface` | `@llvm-project//mlir:InferTypeOpInterface` |
   | `MLIRInferIntRangeInterface` | `@llvm-project//mlir:InferIntRangeInterface` |
   | `MLIRInferIntRangeCommon` | `@llvm-project//mlir:InferIntRangeCommon` |
   | `MLIRMemorySlotInterfaces` | `@llvm-project//mlir:MemorySlotInterfaces` |
   | `LINK_COMPONENTS Support/Core` | `@llvm-project//llvm:Support` / `:Core` |

   Note that Bazel's `deps` are transitive, so unlike CMake `LINK_LIBS PUBLIC`
   you only need the *direct* dependencies, but adding the CMake ones is a safe
   and mechanical default.

3. **Non-source headers in `lib/`** (e.g. `ExportVerilogInternals.h`,
   `lib/Dialect/SV/ReservedWords.def`) must be listed in the library's `hdrs`
   so they are present in the sandbox.

4. **Register it in the docs:** add a row to the table in §5, or to §6 if it
   stays out of scope.

5. Build:

   ```bash
   bazel build //lib/Dialect/Foo:circt_foo
   ```

## 8. Optional dependencies (explicitly excluded)

| Feature | Upstream switch | Why excluded |
| --- | --- | --- |
| CaDiCaL SAT solver | `CIRCT_CADICAL_ENABLED` | external C++ dep; `SATSolver.cpp` has a fallback |
| Z3 / SMT lowering | `CIRCT_SMT_*` | external dep, not needed for HW/Comb/SV |
| Cap'n Proto / ESI | `CIRCT_ESI_*` | external codegen + runtime |
| Python bindings, C API | `CIRCT_BINDINGS_PYTHON_ENABLED` | different packaging model; out of scope |
| Tools/tests/docs | - | not libraries; use the CMake build for `circt-opt` |

None of these are referenced by the covered targets.

## 9. Known issue: `MapVector` with newer LLVM

LLVM commit `145af0deae5` added `mlir::MapVector`. CIRCT's
`include/circt/Support/LLVM.h` used to re-export `llvm::MapVector` into
namespace `circt`, which makes unqualified `MapVector` ambiguous in translation
units with both `using namespace mlir;` and `using namespace circt;`
(`lib/Dialect/FIRRTL/FIRRTLReductions.cpp` and
`lib/Target/DebugInfo/EmitHGLDD.cpp` are the known cases).

**Policy:** the overlay carries a one-line compatibility change on this branch,
in `include/circt/Support/LLVM.h`:

```cpp
using mlir::MapVector;
```

* Minimum LLVM revision: `145af0deae5`.
* Upstream sources are otherwise untouched.
* Consumers tracking an older LLVM (before `145af0deae5`) must either stay on
  an older CIRCT branch or revert that line; consumers on newer LLVM need to
  do nothing.
* `llvm::SmallMapVector` is unaffected and still re-exported from `circt`.

## 10. Refresh procedure

After moving CIRCT (`git submodule update --remote third_party/circt`):

```bash
# 1. The target graph must still load; catches removed/renamed packages.
bazel query '//lib/...' '//include/...'

# 2. TableGen wiring: build all generated headers (fast, no C++ compile).
bazel build //include/...

# 3. Compile the covered libraries.
bazel build //lib/...

# 4. Format/lint the BUILD files.
buildifier -mode=check -lint=warn $(git ls-files '*BUILD.bazel' '*.bzl' MODULE.bazel)
```

Then diff the overlay against CMake:

```bash
for d in lib/Support lib/Dialect/HW lib/Dialect/Comb lib/Dialect/Seq \
         lib/Dialect/SV lib/Conversion/ExportVerilog lib/Conversion/SeqToSV; do
  git diff HEAD~1 -- $d/CMakeLists.txt
done
```

Common refresh failures and fixes:

| Symptom | Fix |
| --- | --- |
| `could not find include file 'circt/.../X.td'` from `mlir-tblgen` in Bazel | add the owning package to that directory's `TD_DEPS` (see `//include/circt/Dialect/Seq`) |
| `could not find include file 'mlir/...'` | add the MLIR `*TdFiles` target to `MLIR_TD_DEPS` in `bazel/circt.bzl` |
| `no such target '@llvm-project//mlir:X'` | MLIR renamed/removed a library; update the mapping in §7 |
| new source file in a covered directory | add it to the `srcs` list (the overlay lists sources explicitly, like CMake) |
| new `add_circt_dialect` output | add the `tbl_outs` entry; the six standard outputs are shown in §7 |
| ambiguous `MapVector` | see §9 |

When moving LLVM (`@llvm-project`), the same two TableGen checks apply; in
addition, watch for new MLIR libraries used by CIRCT and for `.td` files that
moved between MLIR targets.

## 11. Validation

`bazel/validation/` contains the script used to validate this overlay without
building LLVM from scratch (it drives the consumer-provided `@llvm-project`):

```bash
# Inside a consumer workspace where @llvm-project already exists (prefix the
# labels with @circt// if CIRCT is consumed as a separate repository):
bazel query 'kind("cc_library|cc_binary", //...)'
bazel build //include/...        # 100 mlir-tblgen actions
bazel build //lib/...            # 13 libraries
bazel build //bazel/smoke:smoke  # optional end-to-end binary
```

See `OVERLAY-STATUS.md` for what was actually run while preparing this branch,
and `bazel/validation/README.md` for the harness details.

## 12. Known limitations

* No `install`/`exports_files`/shared-library packaging rules: the overlay is
  meant for *consumption inside a Bazel build*, not for producing a CIRCT SDK.
* No Python bindings, no `circt-opt`-style tools, no lit tests.
* `Version.cpp` is generated with the literal string `bazel-overlay` instead of
  the git hash (Bazel builds should be hermetic and cacheable). Override
  `//lib/Support:version_cpp` if you need a real version string.
* Header `:headers` targets use `strip_include_prefix`; this requires Bazel >= 5
  (repo-root-relative strip prefixes). Validated on Bazel 8.4.2.
* No `layering_check`/`parse_headers` features are enabled, so header deps are
  not strictly enforced. If you enable them, expect to add some header-only
  deps.

## 13. Troubleshooting

* **`Every .bzl file must have a corresponding package`** - you copied the
  overlay into a tree without `bazel/BUILD.bazel`; keep the overlay intact or
  use model A (repository boundary).
* **`@llvm-project//... does not resolve`** - in model A, the repo must be
  visible in the consumer's repo mapping (a repo rule/extension of the main
  module); in model B, `llvm-project-overlay` must be overridden to a real
  module or repo.
* **`no such package '@circt//...'`** - in model A use
  `local_repository(name = "circt", ...)`; do not place the overlay's BUILD
  files directly under your main module.
* **TableGen output not found by the compiler** - the `:headers` target must
  depend on the `gentbl` target that produces the `.inc` file. Generated
  headers are exposed as `circt/...` via `strip_include_prefix`.
