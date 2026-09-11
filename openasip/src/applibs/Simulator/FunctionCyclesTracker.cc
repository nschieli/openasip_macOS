/*
    Copyright (c) 2002-2026 Tampere University.
    Copyright (c) 2026 Nicolas Schieli.

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
 * @file FunctionCyclesTracker.cc
 *
 * Implementation of FunctionCyclesTracker class.
 */

#include "FunctionCyclesTracker.hh"

#include <algorithm>

#include "CodeSnippet.hh"
#include "ControlUnit.hh"
#include "Instruction.hh"
#include "Machine.hh"
#include "Move.hh"
#include "Procedure.hh"
#include "Program.hh"
#include "SimulationEventHandler.hh"
#include "SimulatorFrontend.hh"
#include "Terminal.hh"
#include "TerminalFUPort.hh"

FunctionCyclesTracker::FunctionCyclesTracker(SimulatorFrontend& frontend) :
    Listener(), frontend_(&frontend),
    previousInstruction_(NULL), previousProcedure_(NULL),
    totalTrackedCycles_(0), unattributedCycles_(0) {
    frontend.eventHandler().registerListener(
        SimulationEventHandler::SE_CYCLE_END, this);
}

FunctionCyclesTracker::FunctionCyclesTracker() :
    Listener(), frontend_(NULL),
    previousInstruction_(NULL), previousProcedure_(NULL),
    totalTrackedCycles_(0), unattributedCycles_(0) {
}

FunctionCyclesTracker::~FunctionCyclesTracker() {
    if (frontend_ != NULL) {
        frontend_->eventHandler().unregisterListener(
            SimulationEventHandler::SE_CYCLE_END, this);
    }
}

void
FunctionCyclesTracker::handleEvent(int event) {
    if (event != SimulationEventHandler::SE_CYCLE_END) {
        return;
    }
    if (frontend_ == NULL || !frontend_->isProgramLoaded()) {
        return;
    }

    const InstructionAddress address = frontend_->lastExecutedInstruction();
    const TTAProgram::Instruction& currentInstruction =
        frontend_->program().instructionAt(address);

    if (!currentInstruction.isInProcedure()) {
        recordUnattributedCycle();
        previousInstruction_ = &currentInstruction;
        previousProcedure_ = NULL;
        return;
    }

    const TTAProgram::CodeSnippet* currentProcedure =
        &currentInstruction.parent();
    const TTAProgram::Procedure* currentProcedureP =
        dynamic_cast<const TTAProgram::Procedure*>(currentProcedure);
    // Procedure name is only available via the Procedure subclass. If the
    // CodeSnippet is something else (unlikely in practice), fall back to
    // the unattributed bucket to keep output names meaningful.
    if (currentProcedureP == NULL) {
        recordUnattributedCycle();
        previousInstruction_ = &currentInstruction;
        previousProcedure_ = currentProcedure;
        return;
    }

    const std::string name = currentProcedureP->name();

    // Detect a procedure transition. Classify entry vs. exit with the same
    // jump-heuristic ProcedureTransferTracker uses: if the last control-flow
    // instruction moved into the jump port, this transition is a return
    // (exit); otherwise it's a call (entry). The first-ever instruction
    // counts as an entry into the initial procedure.
    if (currentProcedure != previousProcedure_) {
        bool isEntry = true;
        if (previousInstruction_ != NULL) {
            const int delaySlots =
                frontend_->machine().controlUnit()->delaySlots();
            const InstructionAddress controlFlowAddr =
                previousInstruction_->address().location() - delaySlots;
            const TTAProgram::Instruction& controlFlowInstr =
                frontend_->program().instructionAt(controlFlowAddr);
            for (int i = 0; i < controlFlowInstr.moveCount(); ++i) {
                TTAProgram::Move& m = controlFlowInstr.move(i);
                if (dynamic_cast<TTAProgram::TerminalFUPort*>(
                        &m.destination()) == NULL) {
                    continue;
                }
                if (m.destination().isOpcodeSetting() && m.isJump()) {
                    isEntry = false;
                    break;
                }
            }
        }
        if (isEntry) {
            recordCall(name);
        }
    }

    recordCycle(name);

    previousInstruction_ = &currentInstruction;
    previousProcedure_ = currentProcedure;
}

void
FunctionCyclesTracker::recordCycle(const std::string& functionName) {
    ++perFunction_[functionName].cycles;
    ++totalTrackedCycles_;
}

void
FunctionCyclesTracker::recordCall(const std::string& functionName) {
    ++perFunction_[functionName].calls;
}

void
FunctionCyclesTracker::recordUnattributedCycle() {
    ++unattributedCycles_;
}

FunctionCyclesTracker::RankedEntries
FunctionCyclesTracker::topByCycles(std::size_t n) const {
    RankedEntries entries;
    entries.reserve(perFunction_.size());
    for (const auto& kv : perFunction_) {
        entries.emplace_back(kv.first, kv.second);
    }
    std::sort(
        entries.begin(), entries.end(),
        [](const std::pair<std::string, Stats>& a,
           const std::pair<std::string, Stats>& b) {
            if (a.second.cycles != b.second.cycles) {
                return a.second.cycles > b.second.cycles;
            }
            return a.first < b.first;
        });
    if (entries.size() > n) {
        entries.resize(n);
    }
    return entries;
}
