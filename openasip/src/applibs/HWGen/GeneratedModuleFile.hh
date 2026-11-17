/*
    Copyright (c) 2026 OpenASIP contributors.

    This file is part of TTA-Based Codesign Environment (TCE).

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
 * @file GeneratedModuleFile.hh
 *
 * Writes the HDL file of a generated (FUGen/RFGen) block.
 */
#pragma once

#include <string>

struct ProGeOptions;

namespace HDLGenerator {
class Module;
}

namespace ProGe {
class NetlistBlock;
}

namespace HWGenTools {

/**
 * Writes a generated block's HDL file and returns the module name used.
 *
 * Without a separate shared directory (the single-core case), the file
 * goes to the core's own output directory under the module's own name, as
 * before.
 *
 * With --shared-files-dir pointing elsewhere, several cores may be
 * generated into one design, and two of them may each have, say, an
 * "fu_alu" that is not the same hardware. The module is then named
 * <name>_<hash>, where <hash> is taken from its generated text (without
 * the timestamped header), and written once to the shared directory.
 * Identical blocks in different cores, even from different ADFs, get the
 * same name and share one file; different blocks get different names. The
 * name depends only on the generated hardware, so regenerating one core
 * never renames the modules of another. The netlist block that
 * instantiates the module is renamed to match.
 */
std::string writeGeneratedModule(
    HDLGenerator::Module& module, const ProGeOptions& options,
    ProGe::NetlistBlock* netlistBlock);

/// True when generated blocks go to a shared directory (see above).
bool usesSharedDirectory(const ProGeOptions& options);

/// FNV-1a 64-bit hash of the text, as 8 lower-case hex digits.
std::string shortHash(const std::string& text);

}  // namespace HWGenTools
