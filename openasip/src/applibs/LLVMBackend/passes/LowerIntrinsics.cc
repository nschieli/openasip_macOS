/*
    Copyright (c) 2002-2025 Tampere University.

    This file is part of OpenASIP.

    Permission is hereby granted, free of charge, to any person obtaining a
    copy of this software and associated documentation files (the "Software"),
    to deal in the Software without restriction, including without limitation
    the rights to use, copy, modify, merge, publish, distribute, sublicense,
    and/or sell copies of the Software, and to permit persons to whom the
    Software is furnished to do so, subject to the following conditions:

    The above copyright notice and this permission notice shall be included in
    all copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
    THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
    FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
    DEALINGS IN THE SOFTWARE.
 */

/**
 * @file LowerIntrinsics.cc
 *
 * Converts llvm intrinsics to libcalls.
 *
 * @author Veli-Pekka Jaaskelainen 2008 (vjaaskel-no.spam-cs.tut.fi)
 * @author Mikael Lepistö 2009 (mikael.lepisto-no.spam-tut.fi)
 * @author Joonas Multanen 2023 (joonas.multanen-no.spam-tuni.fi)
 */

#include <CompilerWarnings.hh>
IGNORE_COMPILER_WARNING("-Wunused-parameter")

#include "tce_config.h"

#include <llvm/Transforms/Scalar.h>
#include <llvm/Transforms/Utils/UnifyFunctionExitNodes.h>
#include <llvm/IR/Module.h>
#include <llvm/IR/Instructions.h>
#include <llvm/IR/Constants.h>
#include <llvm/IR/Intrinsics.h>
#include <llvm/IR/DerivedTypes.h>
#include <llvm/IR/LLVMContext.h>
#include <llvm/Support/Compiler.h>
#include <llvm/IR/Function.h>
#include <llvm/Pass.h>
#include <llvm/Passes/PassBuilder.h>
#if LLVM_MAJOR_VERSION < 22
#include <llvm/Passes/PassPlugin.h>
#else
#include <llvm/Plugins/PassPlugin.h>
#endif
#include <llvm/CodeGen/IntrinsicLowering.h>
#include <llvm/IR/IntrinsicInst.h>
#include <llvm/IR/IRBuilder.h>
#include <llvm/Analysis/TargetTransformInfo.h>
#include <llvm/Analysis/TargetTransformInfoImpl.h>
#include <llvm/Transforms/Utils/LowerMemIntrinsics.h>

POP_COMPILER_DIAGS

#include <llvm/IR/DataLayout.h>
typedef llvm::DataLayout TargetData;

using namespace llvm;

#include <iostream>
#include <memory>
#include <set>

namespace {

/// Size in bytes of the widest access, at most a 32-bit word, that the
/// alignment allows.
unsigned
memAccessUnit(Align alignment) {
    return std::min<uint64_t>(alignment.value(), 4);
}

#if LLVM_MAJOR_VERSION >= 21
/**
 * Picks the access types of the expanded memcpy and memmove loops.
 *
 * The default implementation copies byte by byte. Copy with the widest
 * access, up to a word, that the alignment of the operands allows instead.
 */
class MemLoopTypeInfo : public TargetTransformInfoImplBase {
public:
    explicit MemLoopTypeInfo(const DataLayout& DL)
        : TargetTransformInfoImplBase(DL) {}

    Type* getMemcpyLoopLoweringType(
        LLVMContext& context, Value*, unsigned, unsigned, Align srcAlign,
        Align dstAlign, std::optional<uint32_t> atomicSize) const override {
        if (atomicSize) {
            return Type::getIntNTy(context, *atomicSize * 8);
        }
        return Type::getIntNTy(
            context, memAccessUnit(std::min(srcAlign, dstAlign)) * 8);
    }

    void getMemcpyLoopResidualLoweringType(
        SmallVectorImpl<Type*>& opsOut, LLVMContext& context,
        unsigned remainingBytes, unsigned, unsigned, Align srcAlign,
        Align dstAlign, std::optional<uint32_t> atomicSize) const override {
        if (atomicSize) {
            for (unsigned i = 0; i < remainingBytes; i += *atomicSize) {
                opsOut.push_back(Type::getIntNTy(context, *atomicSize * 8));
            }
            return;
        }
        // The residual starts at a multiple of the loop access size, so
        // accesses of decreasing size keep their natural alignment.
        unsigned unit = memAccessUnit(std::min(srcAlign, dstAlign));
        for (; unit > 0; unit /= 2) {
            for (; remainingBytes >= unit; remainingBytes -= unit) {
                opsOut.push_back(Type::getIntNTy(context, unit * 8));
            }
        }
    }
};
#endif

}


class LowerIntrinsics : public PassInfoMixin<LowerIntrinsics> {
public:
    PreservedAnalyses run(Function &F, FunctionAnalysisManager &AM);

    /// The memory intrinsics in non-default address spaces must be expanded
    /// in optnone (-O0) functions too, as the code generator would replace
    /// the larger ones with calls to the address space 0 library routines.
    static bool isRequired() { return true; }

    // to suppress Clang warnings
    //using llvm::FunctionPass::doInitialization;
    //using llvm::FunctionPass::doFinalization;

    bool runOnBasicBlock(BasicBlock &BB);

private:
    bool expandMemIntrinsicInline(CallInst* ci);
    bool doInitialization(Module &M);
    bool doFinalization (Module &M);
    /// List of intrinsics to replace.
    std::set<unsigned> replace_;
    IntrinsicLowering* iLowering_;
    /// Picks the access types of the expanded memory operation loops.
    std::unique_ptr<TargetTransformInfo> tti_;
    /// In optnone functions only the memory intrinsics that access a
    /// non-default address space are lowered, the rest is left to the code
    /// generator as before this pass was required.
    bool nonDefaultAddressSpacesOnly_ = false;
    /// True if a memory intrinsic was expanded, which changes the CFG.
    bool expandedInline_ = false;
};

PreservedAnalyses
LowerIntrinsics::run(Function& F, FunctionAnalysisManager&) {
    //errs() << F.getName() << "\n";
  Module *parentModule = F.getParent();
#if LLVM_MAJOR_VERSION >= 21
  tti_ = std::make_unique<TargetTransformInfo>(
      std::make_unique<MemLoopTypeInfo>(parentModule->getDataLayout()));
#else
  tti_ = std::make_unique<TargetTransformInfo>(parentModule->getDataLayout());
#endif
  nonDefaultAddressSpacesOnly_ = F.hasOptNone();
  expandedInline_ = false;
  doInitialization(*parentModule);
  for (BasicBlock &BB : F) {
      runOnBasicBlock(BB);
  }
  doFinalization(*parentModule);
  if (expandedInline_) {
      return PreservedAnalyses::none();
  }
  return PreservedAnalyses::all();
}

bool
LowerIntrinsics::doInitialization(Module &M) {

    // Initialize list of intrinsics to lower.
    replace_.insert(Intrinsic::get_rounding);
    replace_.insert(Intrinsic::ceil);
    replace_.insert(Intrinsic::floor);
    replace_.insert(Intrinsic::round);
    replace_.insert(Intrinsic::exp2);
    replace_.insert(Intrinsic::memcpy);
    replace_.insert(Intrinsic::memset);
    replace_.insert(Intrinsic::memmove);

    assert(iLowering_ == NULL);
#if LLVM_MAJOR_VERSION < 21
    DataLayout* DL = new DataLayout(&M);
    iLowering_ = new IntrinsicLowering(*DL);
    delete DL;
#else
    iLowering_ = new IntrinsicLowering(M.getDataLayout());
#endif
    return true;
}

bool
LowerIntrinsics::doFinalization(Module& /*M*/) {
    if (iLowering_ != NULL) {
        delete iLowering_;
        iLowering_ = NULL;
    }
    return true;
}

/**
 * Expands a memcpy, memmove or memset intrinsic that accesses a
 * non-default address space as a loop of loads and stores.
 *
 * The C library routines memcpy, memmove and memset take pointers to the
 * default address space 0. Replacing the intrinsic with a call to them
 * would make them access address space 0 with the address of the other
 * address space, so these intrinsics are expanded inline, which keeps the
 * address space of each pointer in the loads and stores.
 *
 * @return True if the intrinsic was expanded and erased, false if it
 * accesses address space 0 only and can be replaced with a library call.
 */
bool
LowerIntrinsics::expandMemIntrinsicInline(CallInst* ci) {
    MemIntrinsic* mi = dyn_cast<MemIntrinsic>(ci);
    if (mi == nullptr) {
        return false;
    }
    unsigned dstAS = mi->getDestAddressSpace();
    MemTransferInst* mti = dyn_cast<MemTransferInst>(mi);
    unsigned srcAS = mti != nullptr ? mti->getSourceAddressSpace() : 0;
    if (dstAS == 0 && srcAS == 0) {
        return false;
    }

    if (MemCpyInst* memcpy = dyn_cast<MemCpyInst>(mi)) {
        expandMemCpyAsLoop(memcpy, *tti_);
    } else if (MemMoveInst* memmove = dyn_cast<MemMoveInst>(mi)) {
        if (srcAS != dstAS) {
            // The address spaces are separate memories, so the source
            // and the destination cannot overlap: copy as a memcpy.
            IRBuilder<> builder(memmove);
            CallInst* memcpy = builder.CreateMemCpy(
                memmove->getRawDest(), memmove->getDestAlign(),
                memmove->getRawSource(), memmove->getSourceAlign(),
                memmove->getLength(), memmove->isVolatile());
            expandMemCpyAsLoop(cast<MemCpyInst>(memcpy), *tti_);
            memcpy->eraseFromParent();
        } else if (!expandMemMoveAsLoop(memmove, *tti_)) {
            report_fatal_error(
                "Cannot expand memmove in address space " + Twine(dstAS));
        }
    } else if (MemSetInst* memset = dyn_cast<MemSetInst>(mi)) {
#if LLVM_MAJOR_VERSION >= 21
        // Store words instead of bytes when the alignment and the
        // constant length allow it.
        ConstantInt* length = dyn_cast<ConstantInt>(memset->getLength());
        unsigned unit = memAccessUnit(memset->getDestAlign().valueOrOne());
        while (length != nullptr && unit > 1 &&
               length->getZExtValue() % unit != 0) {
            unit /= 2;
        }
        if (length != nullptr && unit > 1) {
            IRBuilder<> builder(memset);
            Type* unitType = builder.getIntNTy(unit * 8);
            uint64_t splat = 0;
            for (unsigned i = 0; i < unit; ++i) {
                splat = (splat << 8) | 1;
            }
            Value* pattern = builder.CreateMul(
                builder.CreateZExt(memset->getValue(), unitType),
                ConstantInt::get(unitType, splat));
            Value* count = ConstantInt::get(
                length->getType(), length->getZExtValue() / unit);
            CallInst* patternSet = builder.CreateIntrinsic(
                Intrinsic::experimental_memset_pattern,
                {memset->getRawDest()->getType(), unitType, count->getType()},
                {memset->getRawDest(), pattern, count,
                 builder.getInt1(memset->isVolatile())});
            patternSet->addParamAttr(
                0, Attribute::getWithAlignment(
                    builder.getContext(), *memset->getDestAlign()));
            expandMemSetPatternAsLoop(cast<MemSetPatternInst>(patternSet));
            patternSet->eraseFromParent();
        } else {
            expandMemSetAsLoop(memset);
        }
#else
        expandMemSetAsLoop(memset);
#endif
    } else {
        return false;
    }
    mi->eraseFromParent();
    expandedInline_ = true;
    return true;
}

bool
LowerIntrinsics::runOnBasicBlock(BasicBlock &BB) {
    bool changed = true;
    while (changed)  {
        changed = false;
        for (BasicBlock::iterator I = BB.begin(), E = BB.end(); I != E; ++I) {
            CallInst* ci = dyn_cast<CallInst>(&(*I));
            if (ci != NULL && ci->arg_size() != 0) {
                Function* callee = ci->getCalledFunction();
                if (callee != NULL && callee->isIntrinsic() &&
                    replace_.find(callee->getIntrinsicID()) != replace_.end()) {
                    if (nonDefaultAddressSpacesOnly_) {
                        if (expandMemIntrinsicInline(ci)) {
                            changed = true;
                            break;
                        }
                    } else if (callee->getIntrinsicID() ==
                               Intrinsic::get_rounding) {
                        // Replace GET_ROUNDING intrinsic with the actual
                        // constant value to avoid stupid  "if (1 == 0)"
                        // code even with full optimizations.
                        I->replaceAllUsesWith(
                            ConstantInt::get(
                                Type::getInt32Ty(BB.getContext()), 0, true));
                        I->eraseFromParent();
                        changed = true;
                        break;
                    } else if (expandMemIntrinsicInline(ci)) {
                        // The expansion splits the basic block: the rest
                        // of it is visited as a new basic block.
                        changed = true;
                        break;
                    } else {
                        iLowering_->LowerIntrinsicCall(ci);
                        changed = true;
                        break;
                    }
                }
            }
        }
    }
    return true;
}


/* New PM Registration */
llvm::PassPluginLibraryInfo getLowerIntrinsicsPluginInfo() {
  return {LLVM_PLUGIN_API_VERSION, "LowerIntrinsics", LLVM_VERSION_STRING,
          [](PassBuilder &PB) {
            PB.registerVectorizerStartEPCallback(
                [](llvm::FunctionPassManager &PM, OptimizationLevel /*Level*/) {
                  PM.addPass(LowerIntrinsics());
                });
            PB.registerPipelineParsingCallback(
                [](StringRef Name, llvm::FunctionPassManager &PM,
                   ArrayRef<llvm::PassBuilder::PipelineElement>) {
                  if (Name == "lowerintrinsic") {
                    PM.addPass(LowerIntrinsics());
                    return true;
                  }
                  return false;
                });
          }};
}

#ifndef LLVM_LOWERINTRINSICS_LINK_INTO_TOOLS
extern "C" LLVM_ATTRIBUTE_WEAK ::llvm::PassPluginLibraryInfo
llvmGetPassPluginInfo() {
  return getLowerIntrinsicsPluginInfo();
}
#endif
