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
 * @file FunctionCyclesTracker.hh
 *
 * Declaration of FunctionCyclesTracker class.
 *
 * Tracks exclusive (self) cycles per procedure + entry counts. The output
 * feeds the "crc32_step is 69% of runtime" attribution the MCP `profile`
 * tool needs — without DWARF, using just the TPEF-backed Procedure names.
 */

#ifndef TTA_FUNCTION_CYCLES_TRACKER_HH
#define TTA_FUNCTION_CYCLES_TRACKER_HH

#include <cstdint>
#include <cstddef>
#include <string>
#include <unordered_map>
#include <utility>
#include <vector>

#include "Listener.hh"

class SimulatorFrontend;

namespace TTAProgram {
    class CodeSnippet;
    class Instruction;
}

/**
 * Accumulates per-procedure cycle counts and entry counts during simulation.
 *
 * Listener on SE_CYCLE_END. Each cycle attributes +1 to the procedure that
 * owns the just-executed instruction (exclusive / self cycles — callers do
 * not absorb callee cycles). When the procedure of the current instruction
 * differs from the previous cycle's procedure, the transition is classified
 * as an entry (call) or an exit (return) using the same heuristic
 * ProcedureTransferTracker uses: if the last control-flow instruction had
 * a jump move it is an exit; otherwise it is an entry.
 *
 * Known limitations (documented rather than engineered around):
 * - Tail calls appear as exit-without-entry; the following procedure is
 *   attributed cycles but its call count may be under-reported.
 * - Non-returning helpers (abort, longjmp targets) skew entry/exit
 *   classification for the affected procedure.
 * - Cycles executed while the current instruction is not inside any
 *   procedure (e.g. raw assembly stubs) are counted as "unattributed".
 * - Interpretive simulator only. The compiled simulator does not drive
 *   SE_CYCLE_END in a form this tracker consumes.
 */
class FunctionCyclesTracker : public Listener {
public:
    struct Stats {
        std::uint64_t cycles = 0;
        std::uint64_t calls = 0;
    };
    typedef std::unordered_map<std::string, Stats> StatsMap;
    typedef std::vector<std::pair<std::string, Stats>> RankedEntries;

    FunctionCyclesTracker(SimulatorFrontend& frontend);

    /// Test-only constructor: does not register with the frontend's event
    /// handler. Drive the counters via recordCycle() / recordCall() in tests.
    FunctionCyclesTracker();

    virtual ~FunctionCyclesTracker();

    virtual void handleEvent(int event);

    /// Record a single cycle of execution attributed to the named function.
    /// Exposed for unit tests.
    void recordCycle(const std::string& functionName);

    /// Record a single entry (call) to the named function. Exposed for
    /// unit tests.
    void recordCall(const std::string& functionName);

    /// Record a cycle whose instruction is not inside any procedure. Exposed
    /// for unit tests.
    void recordUnattributedCycle();

    std::uint64_t totalTrackedCycles() const { return totalTrackedCycles_; }
    std::uint64_t unattributedCycles() const { return unattributedCycles_; }
    std::size_t functionCount() const { return perFunction_.size(); }

    const StatsMap& perFunction() const { return perFunction_; }

    /// Top-N functions by cycle count, descending. Ties broken lexicographically.
    RankedEntries topByCycles(std::size_t n) const;

private:
    SimulatorFrontend* frontend_;

    const TTAProgram::Instruction* previousInstruction_;
    const TTAProgram::CodeSnippet* previousProcedure_;

    StatsMap perFunction_;
    std::uint64_t totalTrackedCycles_;
    std::uint64_t unattributedCycles_;
};

#endif
