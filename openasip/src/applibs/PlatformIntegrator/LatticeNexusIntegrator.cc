/*
    Copyright (c) 2026 Nicolas Schieli.

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
 * @file LatticeNexusIntegrator.cc
 *
 * Implementation of LatticeNexusIntegrator class.
 *
 * Platform integrator for Lattice CertusPro-NX FPGAs, targeting the open-source
 * Yosys + Lattice Radiant synthesis toolchain. Uses XilinxBlockRamGenerator
 * for memory (behavioral VHDL that Yosys infers as PDP16K on CertusPro-NX).
 *
 * @author Nicolas Schieli 2026
 * @note rating: red
 */

#include "LatticeNexusIntegrator.hh"
#include "Exception.hh"
#include "MemoryGenerator.hh"
#include "XilinxBlockRamGenerator.hh"
#include "VhdlRomGenerator.hh"
#include "StringTools.hh"
#include "NetlistBlock.hh"
#include "FileSystem.hh"
using std::vector;
using std::endl;

const TCEString LatticeNexusIntegrator::DEFAULT_DEVICE_FAMILY_ = "CrossLink-NX";
const TCEString LatticeNexusIntegrator::DEVICE_PACKAGE_ = "csBGA289";
const TCEString LatticeNexusIntegrator::DEVICE_SPEED_CLASS_ = "8";
const TCEString LatticeNexusIntegrator::PIN_TAG_ = "LATTICE_NEXUS";
const int LatticeNexusIntegrator::DEFAULT_FREQ_ = 50;


LatticeNexusIntegrator::LatticeNexusIntegrator():
    PlatformIntegrator(),
    deviceFamily_(DEFAULT_DEVICE_FAMILY_),
    imemGen_(NULL), dmemGen_(NULL) {
}


LatticeNexusIntegrator::LatticeNexusIntegrator(
    const TTAMachine::Machine* machine,
    const IDF::MachineImplementation* idf,
    ProGe::HDL hdl,
    TCEString progeOutputDir,
    TCEString coreEntityName,
    TCEString outputDir,
    TCEString programName,
    int targetClockFreq,
    std::ostream& warningStream,
    std::ostream& errorStream,
    const MemInfo& imem,
    MemType dmemType):
    PlatformIntegrator(machine, idf, hdl, progeOutputDir, coreEntityName,
                       outputDir, programName, targetClockFreq, warningStream,
                       errorStream, imem, dmemType),
    deviceFamily_(DEFAULT_DEVICE_FAMILY_),
    imemGen_(NULL), dmemGen_(NULL) {
}


LatticeNexusIntegrator::~LatticeNexusIntegrator() {

    if (imemGen_ != NULL) {
        delete imemGen_;
    }
    if (dmemGen_ != NULL) {
        delete dmemGen_;
    }
}


void
LatticeNexusIntegrator::integrateProcessor(
    const ProGe::NetlistBlock* ttaCore) {

    initPlatformNetlist(ttaCore);

    // Use default core integration (no Lattice-specific modifications)
    const ProGe::NetlistBlock& core = progeBlock();
    if (!integrateCore(core, 0)) {
        return;
    }

    exportUnconnectedPorts(0);
    writeNewToplevel();
}


TCEString
LatticeNexusIntegrator::deviceFamily() const {
    return deviceFamily_;
}


void
LatticeNexusIntegrator::setDeviceFamily(TCEString devFamily) {
    deviceFamily_ = devFamily;
}


TCEString
LatticeNexusIntegrator::devicePackage() const {
    return DEVICE_PACKAGE_;
}


TCEString
LatticeNexusIntegrator::deviceSpeedClass() const {
    return DEVICE_SPEED_CLASS_;
}


int
LatticeNexusIntegrator::targetClockFrequency() const {
    return DEFAULT_FREQ_;
}


TCEString
LatticeNexusIntegrator::pinTag() const {
    return PIN_TAG_;
}


bool
LatticeNexusIntegrator::chopTaggedSignals() const {
    return false;
}


ProjectFileGenerator*
LatticeNexusIntegrator::projectFileGenerator() const {
    // Yosys/nextpnr use command-line arguments, no project file needed.
    // Return NULL to skip project file generation.
    return NULL;
}


MemoryGenerator&
LatticeNexusIntegrator::imemInstance(MemInfo imem, int coreId) {

    if (imemGen_ == NULL) {
        if (imem.type == VHDL_ARRAY) {
            TCEString initFile = programName() + "_imem_pkg.vhdl";
            imemGen_ = new VhdlRomGenerator(
                imem.mauWidth, imem.widthInMaus, imem.portAddrw,
                initFile, this, warningStream(), errorStream());
        } else if (imem.type == ONCHIP) {
            // Use XilinxBlockRamGenerator — its behavioral VHDL pattern
            // is also inferred as BRAM (DP16KD) by Yosys on ECP5.
            int addrw = imem.portAddrw;
            imemGen_ = new XilinxBlockRamGenerator(
                imem.mauWidth, imem.widthInMaus, addrw,
                0, 0,  // portBDataWidth, portBAddrWidth (single-port)
                this, warningStream(), errorStream());
        } else {
            TCEString msg = "Unsupported instruction memory type for "
                "Lattice CertusPro-NX. Use 'vhdl_array' or 'onchip'.";
            throw InvalidData(__FILE__, __LINE__,
                "LatticeNexusIntegrator::imemInstance", msg);
        }
    }
    return *imemGen_;
}


MemoryGenerator&
LatticeNexusIntegrator::dmemInstance(
    MemInfo dmem, TTAMachine::FunctionUnit& lsuArch,
    std::vector<std::string> lsuPorts) {

    if (dmemGen_ == NULL) {
        if (dmem.type == ONCHIP) {
            TCEString initFile = programName() + "_" + dmem.asName + ".mif";
            int addrw = dmem.portAddrw;
            // XilinxBlockRamGenerator with lattice-compatible defaults.
            // The behavioral VHDL is vendor-neutral; Yosys infers DP16KD.
            dmemGen_ = new XilinxBlockRamGenerator(
                dmem.mauWidth, dmem.widthInMaus, addrw,
                0, 0,  // portBDataWidth, portBAddrWidth (single-port)
                this, warningStream(), errorStream());
            dmemGen_->addLsu(lsuArch, lsuPorts);
        } else {
            TCEString msg = "Unsupported data memory type for Lattice CertusPro-NX. "
                "Use 'onchip'.";
            throw InvalidData(__FILE__, __LINE__,
                "LatticeNexusIntegrator::dmemInstance", msg);
        }
    }
    return *dmemGen_;
}


void
LatticeNexusIntegrator::printInfo(std::ostream& stream) const {

    stream
        << "Integrator name: LatticeNexusIntegrator" << endl
        << "--------------------------------------" << endl
        << "Platform integrator for Lattice CertusPro-NX FPGAs." << endl
        << "Targets Yosys + nextpnr-nexus (open-source) or Lattice Radiant." << endl
        << "Primary device: CrossLink-NX LIFCL-40 (csBGA289)." << endl
        << endl
        << "Supported instruction memory types: 'onchip', 'vhdl_array'."
        << endl
        << "Supported data memory type: 'onchip'." << endl
        << "Default clock frequency: " << DEFAULT_FREQ_ << " MHz." << endl
        << "Default device family: " << DEFAULT_DEVICE_FAMILY_ << endl
        << endl
        << "Uses behavioral VHDL patterns for BRAM inference (DP16KD)."
        << endl
        << "No vendor IP cores or project files required." << endl
        << endl;
}
