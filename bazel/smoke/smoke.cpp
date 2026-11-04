//===- smoke.cpp - minimal CIRCT overlay smoke test ----------------------===//
//
// Builds a tiny `hw.module` containing an `hw.constant` and a `comb.xor` and
// prints it. This exercises the HW and Comb dialects, their TableGen output,
// and CIRCTSupport.
//
// Build with:
//   bazel build //bazel/smoke:smoke --cxxopt=-std=c++20
//
// NOTE: the overlay itself does not link against a real MLIR by default; the
// consumer's @llvm-project provides the actual libraries. See
// bazel/smoke/README.md.

#include "circt/Dialect/Comb/CombOps.h"
#include "circt/Dialect/HW/HWOps.h"
#include "llvm/Support/raw_ostream.h"
#include "mlir/IR/Builders.h"
#include "mlir/IR/MLIRContext.h"
#include "mlir/IR/Verifier.h"

using namespace mlir;

int main() {
  MLIRContext context;
  context.loadDialect<circt::hw::HWDialect, circt::comb::CombDialect>();

  OpBuilder builder(&context);
  auto loc = builder.getUnknownLoc();

  // `hw.module @top()` with no ports.
  auto top = circt::hw::HWModuleOp::create(
      builder, loc, builder.getStringAttr("top"),
      ArrayRef<circt::hw::PortInfo>());

  // Insert an `hw.constant` and a `comb.xor` into the module body, before the
  // `hw.output` terminator that the builder created.
  OpBuilder::InsertionGuard guard(builder);
  builder.setInsertionPointToStart(top.getBodyBlock());
  auto constant =
      circt::hw::ConstantOp::create(builder, loc, builder.getI32IntegerAttr(42));
  auto xorOp = circt::comb::XorOp::create(builder, loc, constant.getResult(),
                                          constant.getResult());

  if (failed(verify(top)))
    return 1;

  top->print(llvm::outs());
  llvm::outs() << "\n";

  // Sanity check: two operands, one result, `i32`.
  if (xorOp.getNumOperands() != 2 || xorOp->getNumResults() != 1 ||
      !xorOp.getResult().getType().isInteger(32))
    return 2;

  return 0;
}
