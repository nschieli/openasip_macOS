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
 * @file GeneratedModuleFile.cc
 *
 * Writes the HDL file of a generated (FUGen/RFGen) block.
 */

#include "GeneratedModuleFile.hh"

#include <cstdint>
#include <cstdio>
#include <fstream>
#include <sstream>
#include <unistd.h>

#include "Exception.hh"
#include "FileSystem.hh"
#include "HDLGenerator.hh"
#include "NetlistBlock.hh"
#include "ProGeOptions.hh"

namespace HWGenTools {

namespace {

struct Target {
    std::string subDir;
    std::string extension;
    HDLGenerator::Language language;
};

Target
targetFor(ProGe::HDL hdl) {
    switch (hdl) {
    case ProGe::HDL::VHDL:
        return {"vhdl", ".vhd", HDLGenerator::Language::VHDL};
    case ProGe::HDL::SV:
        return {"systemverilog", ".sv", HDLGenerator::Language::Verilog};
    default:
        return {"verilog", ".v", HDLGenerator::Language::Verilog};
    }
}

/// The generated text without its leading comment, which holds a timestamp.
std::string
withoutHeaderComment(const std::string& text, HDLGenerator::Language lang) {
    size_t pos = 0;
    if (lang == HDLGenerator::Language::VHDL) {
        while (text.compare(pos, 2, "--") == 0) {
            size_t eol = text.find('\n', pos);
            if (eol == std::string::npos) return "";
            pos = eol + 1;
        }
    } else if (text.compare(0, 2, "/*") == 0) {
        size_t end = text.find("*/");
        if (end == std::string::npos) return text;
        pos = end + 2;
    }
    return text.substr(pos);
}

void
writeModule(
    HDLGenerator::Module& module, const Target& target,
    const std::string& file) {
    std::ofstream ofs(file);
    module.implement(ofs, target.language);
    if (!ofs) {
        throw IOException(
            __FILE__, __LINE__, __func__, "Unable to write " + file + ".");
    }
}

}  // namespace

std::string
shortHash(const std::string& text) {
    uint64_t hash = 0xcbf29ce484222325ULL;
    for (unsigned char c : text) {
        hash ^= c;
        hash *= 0x100000001b3ULL;
    }
    char buf[9];
    std::snprintf(
        buf, sizeof(buf), "%08x",
        static_cast<unsigned>((hash >> 32) ^ (hash & 0xffffffffULL)));
    return buf;
}

bool
usesSharedDirectory(const ProGeOptions& options) {
    return !options.sharedOutputDirectory.empty() &&
           FileSystem::absolutePathOf(options.sharedOutputDirectory) !=
               FileSystem::absolutePathOf(options.outputDirectory);
}

std::string
writeGeneratedModule(
    HDLGenerator::Module& module, const ProGeOptions& options,
    ProGe::NetlistBlock* netlistBlock) {
    const std::string DS = FileSystem::DIRECTORY_SEPARATOR;
    Target target = targetFor(options.language);

    if (!usesSharedDirectory(options)) {
        std::string dir = options.outputDirectory + DS + target.subDir;
        FileSystem::createDirectory(dir);
        writeModule(
            module, target, dir + DS + module.name() + target.extension);
        return module.name();
    }

    std::ostringstream text;
    module.implement(text, target.language);
    std::string name = module.name() + "_" +
        shortHash(withoutHeaderComment(text.str(), target.language));
    module.setName(name);
    if (netlistBlock != nullptr) {
        netlistBlock->setModuleName(name);
    }

    std::string dir = options.sharedOutputDirectory + DS + target.subDir;
    std::string file = dir + DS + name + target.extension;
    if (FileSystem::fileExists(file)) {
        // Same name means same hardware: another core already wrote it.
        return name;
    }
    FileSystem::createDirectory(dir);
    // Write under a private name and rename, so that cores generated in
    // parallel into one shared directory never see a partial file.
    std::string tmp = file + ".tmp" + std::to_string(getpid());
    writeModule(module, target, tmp);
    if (std::rename(tmp.c_str(), file.c_str()) != 0) {
        FileSystem::removeFileOrDirectory(tmp);
        throw IOException(
            __FILE__, __LINE__, __func__, "Unable to write " + file + ".");
    }
    return name;
}

}  // namespace HWGenTools
