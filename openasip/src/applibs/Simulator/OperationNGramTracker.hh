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
 * @file OperationNGramTracker.hh
 *
 * Declaration of OperationNGramTracker class.
 *
 * Maintains a rolling window of the most recently triggered operations and
 * accumulates bigram and trigram histograms over the execution stream. This
 * surfaces which operation sequences dominate the dynamic trace — a direct
 * signal for fused / custom-op design work.
 */

#ifndef TTA_OPERATION_N_GRAM_TRACKER_HH
#define TTA_OPERATION_N_GRAM_TRACKER_HH

#include <cstdint>
#include <cstddef>
#include <deque>
#include <string>
#include <unordered_map>
#include <vector>

#include "Listener.hh"

class SimulatorFrontend;

/**
 * Records execution-order op-code n-grams during simulation.
 *
 * Registers for SE_NEW_INSTRUCTION so that frontend_.lastExecutedInstruction()
 * resolves to the instruction whose moves just executed in the previous cycle.
 * For every triggering move in that instruction (in move-slot order) the
 * destination operation name is pushed onto a rolling window, and the bigram
 * / trigram counters keyed by the window suffix are incremented. Squashed
 * moves (conditional execution, guard=false) are skipped.
 *
 * The counters are end-of-run aggregate totals — no per-cycle storage, no
 * trace file. Consumers (InfoStatsCommand, InfoProcCommand) read the top-N
 * entries after the run finishes.
 *
 * Known limitations:
 * - Interpretive simulator (SimulationController) only. The compiled simulator
 *   does not drive SE_NEW_INSTRUCTION per cycle in a form this tracker can use.
 * - The very last executed cycle is not counted (SE_NEW_INSTRUCTION does not
 *   fire on the terminating cycle). For any non-trivial program the shift is
 *   one op in millions and does not change relative frequencies.
 */
class OperationNGramTracker : public Listener {
public:
    typedef std::unordered_map<std::string, std::uint64_t> NGramCounts;
    typedef std::vector<std::pair<std::string, std::uint64_t>> RankedEntries;

    OperationNGramTracker(SimulatorFrontend& frontend);

    /// Test-only constructor: builds a tracker with no frontend wiring.
    /// Callers must exercise the counters via recordOperation() directly;
    /// handleEvent() is a no-op in this mode.
    OperationNGramTracker();

    virtual ~OperationNGramTracker();

    virtual void handleEvent(int event);

    /// Record a single operation execution. Pushes it onto the rolling
    /// window and updates the bigram / trigram counters. Made public so
    /// unit tests can exercise the counter logic without driving a real
    /// simulation.
    void recordOperation(const std::string& opName);

    std::uint64_t totalOperations() const { return totalOps_; }
    std::uint64_t totalBigrams() const { return totalBigrams_; }
    std::uint64_t totalTrigrams() const { return totalTrigrams_; }

    const NGramCounts& bigrams() const { return bigrams_; }
    const NGramCounts& trigrams() const { return trigrams_; }

    /// Top-N bigrams by count, descending. Ties broken by lexicographic key.
    RankedEntries topBigrams(std::size_t n) const;
    /// Top-N trigrams by count, descending. Ties broken by lexicographic key.
    RankedEntries topTrigrams(std::size_t n) const;

    /// Separator between op names in n-gram keys. Public so the formatting
    /// code in InfoCommand can split keys if needed.
    static const char* const SEPARATOR;

private:
    static RankedEntries topN(const NGramCounts& counts, std::size_t n);

    SimulatorFrontend* frontend_;
    /// Rolling window of the last 3 op names executed. Front = oldest.
    std::deque<std::string> window_;
    NGramCounts bigrams_;
    NGramCounts trigrams_;
    std::uint64_t totalOps_;
    std::uint64_t totalBigrams_;
    std::uint64_t totalTrigrams_;
};

#endif
