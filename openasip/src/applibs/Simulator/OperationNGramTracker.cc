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
 * @file OperationNGramTracker.cc
 *
 * Implementation of OperationNGramTracker class.
 */

#include "OperationNGramTracker.hh"

#include <algorithm>

#include "BaseFUPort.hh"
#include "ExecutableInstruction.hh"
#include "Instruction.hh"
#include "Move.hh"
#include "Operation.hh"
#include "Program.hh"
#include "SimulationEventHandler.hh"
#include "SimulatorFrontend.hh"
#include "StringTools.hh"
#include "Terminal.hh"

const char* const OperationNGramTracker::SEPARATOR = " -> ";

OperationNGramTracker::OperationNGramTracker(SimulatorFrontend& frontend) :
    Listener(), frontend_(&frontend),
    totalOps_(0), totalBigrams_(0), totalTrigrams_(0) {
    frontend.eventHandler().registerListener(
        SimulationEventHandler::SE_NEW_INSTRUCTION, this);
}

OperationNGramTracker::OperationNGramTracker() :
    Listener(), frontend_(NULL),
    totalOps_(0), totalBigrams_(0), totalTrigrams_(0) {
}

OperationNGramTracker::~OperationNGramTracker() {
    if (frontend_ != NULL) {
        frontend_->eventHandler().unregisterListener(
            SimulationEventHandler::SE_NEW_INSTRUCTION, this);
    }
}

void
OperationNGramTracker::handleEvent(int event) {
    if (event != SimulationEventHandler::SE_NEW_INSTRUCTION) {
        return;
    }
    if (frontend_ == NULL || !frontend_->isProgramLoaded()) {
        return;
    }

    const InstructionAddress address = frontend_->lastExecutedInstruction();
    const TTAProgram::Instruction& instruction =
        frontend_->program().instructionAt(address);
    const ExecutableInstruction& execInstruction =
        frontend_->executableInstructionAt(address);

    for (int i = 0; i < instruction.moveCount(); ++i) {
        if (execInstruction.moveSquashed(i)) {
            continue;
        }
        const TTAProgram::Move& move = instruction.move(i);
        if (!move.destination().isFUPort()) {
            continue;
        }
        const TTAMachine::BaseFUPort& port =
            dynamic_cast<const TTAMachine::BaseFUPort&>(
                move.destination().port());
        if (!port.isTriggering()) {
            continue;
        }

        recordOperation(StringTools::stringToUpper(
            move.destination().operation().name()));
    }
}

void
OperationNGramTracker::recordOperation(const std::string& opName) {
    window_.push_back(opName);
    if (window_.size() > 3) {
        window_.pop_front();
    }
    ++totalOps_;

    const std::size_t w = window_.size();
    if (w >= 2) {
        const std::string key =
            window_[w - 2] + SEPARATOR + window_[w - 1];
        ++bigrams_[key];
        ++totalBigrams_;
    }
    if (w >= 3) {
        const std::string key =
            window_[w - 3] + SEPARATOR +
            window_[w - 2] + SEPARATOR +
            window_[w - 1];
        ++trigrams_[key];
        ++totalTrigrams_;
    }
}

OperationNGramTracker::RankedEntries
OperationNGramTracker::topN(const NGramCounts& counts, std::size_t n) {
    RankedEntries entries;
    entries.reserve(counts.size());
    for (const auto& kv : counts) {
        entries.emplace_back(kv.first, kv.second);
    }
    std::sort(
        entries.begin(), entries.end(),
        [](const std::pair<std::string, std::uint64_t>& a,
           const std::pair<std::string, std::uint64_t>& b) {
            if (a.second != b.second) return a.second > b.second;
            return a.first < b.first;
        });
    if (entries.size() > n) {
        entries.resize(n);
    }
    return entries;
}

OperationNGramTracker::RankedEntries
OperationNGramTracker::topBigrams(std::size_t n) const {
    return topN(bigrams_, n);
}

OperationNGramTracker::RankedEntries
OperationNGramTracker::topTrigrams(std::size_t n) const {
    return topN(trigrams_, n);
}
