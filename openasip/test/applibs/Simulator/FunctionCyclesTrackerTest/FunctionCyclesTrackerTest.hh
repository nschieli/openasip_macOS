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
 * @file FunctionCyclesTrackerTest.hh
 *
 * Unit tests for the counter logic in FunctionCyclesTracker. Drives the
 * tracker via the test-only constructor — does not run a real simulator.
 */

#ifndef FUNCTION_CYCLES_TRACKER_TEST_HH
#define FUNCTION_CYCLES_TRACKER_TEST_HH

#include <TestSuite.h>

#include "FunctionCyclesTracker.hh"

class FunctionCyclesTrackerTest : public CxxTest::TestSuite {
public:
    void testEmptyStartsAtZero();
    void testRecordCycleAccumulates();
    void testRecordCallAccumulates();
    void testCyclesAndCallsAreIndependent();
    void testUnattributedCyclesNotInTotalTracked();
    void testTopRankedByCyclesThenLex();
    void testTopNRespectsLimit();
};

inline void
FunctionCyclesTrackerTest::testEmptyStartsAtZero() {
    FunctionCyclesTracker t;
    TS_ASSERT_EQUALS(t.totalTrackedCycles(), 0u);
    TS_ASSERT_EQUALS(t.unattributedCycles(), 0u);
    TS_ASSERT_EQUALS(t.functionCount(), 0u);
    TS_ASSERT(t.perFunction().empty());
}

inline void
FunctionCyclesTrackerTest::testRecordCycleAccumulates() {
    FunctionCyclesTracker t;
    for (int i = 0; i < 7; ++i) t.recordCycle("main");
    for (int i = 0; i < 3; ++i) t.recordCycle("inner");
    TS_ASSERT_EQUALS(t.totalTrackedCycles(), 10u);
    TS_ASSERT_EQUALS(t.perFunction().at("main").cycles, 7u);
    TS_ASSERT_EQUALS(t.perFunction().at("inner").cycles, 3u);
    TS_ASSERT_EQUALS(t.functionCount(), 2u);
}

inline void
FunctionCyclesTrackerTest::testRecordCallAccumulates() {
    FunctionCyclesTracker t;
    t.recordCall("main");
    t.recordCall("inner");
    t.recordCall("inner");
    t.recordCall("inner");
    // recordCall on its own does not bump cycles.
    TS_ASSERT_EQUALS(t.totalTrackedCycles(), 0u);
    TS_ASSERT_EQUALS(t.perFunction().at("main").calls, 1u);
    TS_ASSERT_EQUALS(t.perFunction().at("inner").calls, 3u);
}

inline void
FunctionCyclesTrackerTest::testCyclesAndCallsAreIndependent() {
    FunctionCyclesTracker t;
    t.recordCall("hot");
    for (int i = 0; i < 42; ++i) t.recordCycle("hot");
    t.recordCall("hot");
    for (int i = 0; i < 8; ++i) t.recordCycle("hot");
    TS_ASSERT_EQUALS(t.perFunction().at("hot").cycles, 50u);
    TS_ASSERT_EQUALS(t.perFunction().at("hot").calls, 2u);
}

inline void
FunctionCyclesTrackerTest::testUnattributedCyclesNotInTotalTracked() {
    FunctionCyclesTracker t;
    t.recordUnattributedCycle();
    t.recordUnattributedCycle();
    t.recordCycle("main");
    // Unattributed cycles live in their own bucket.
    TS_ASSERT_EQUALS(t.totalTrackedCycles(), 1u);
    TS_ASSERT_EQUALS(t.unattributedCycles(), 2u);
    TS_ASSERT_EQUALS(t.functionCount(), 1u);
}

inline void
FunctionCyclesTrackerTest::testTopRankedByCyclesThenLex() {
    FunctionCyclesTracker t;
    for (int i = 0; i < 50; ++i) t.recordCycle("bbb");
    for (int i = 0; i < 50; ++i) t.recordCycle("aaa");  // tie → lex first
    for (int i = 0; i < 10; ++i) t.recordCycle("ccc");
    auto top = t.topByCycles(3);
    TS_ASSERT_EQUALS(top.size(), 3u);
    // Ties broken lexicographically ascending: "aaa" before "bbb".
    TS_ASSERT_EQUALS(top[0].first,         "aaa");
    TS_ASSERT_EQUALS(top[0].second.cycles, 50u);
    TS_ASSERT_EQUALS(top[1].first,         "bbb");
    TS_ASSERT_EQUALS(top[1].second.cycles, 50u);
    TS_ASSERT_EQUALS(top[2].first,         "ccc");
    TS_ASSERT_EQUALS(top[2].second.cycles, 10u);
}

inline void
FunctionCyclesTrackerTest::testTopNRespectsLimit() {
    FunctionCyclesTracker t;
    for (int i = 0; i < 3; ++i) t.recordCycle("a");
    for (int i = 0; i < 2; ++i) t.recordCycle("b");
    for (int i = 0; i < 1; ++i) t.recordCycle("c");

    auto top0    = t.topByCycles(0);
    auto top1    = t.topByCycles(1);
    auto topMany = t.topByCycles(100);
    TS_ASSERT(top0.empty());
    TS_ASSERT_EQUALS(top1.size(), 1u);
    TS_ASSERT_EQUALS(top1[0].first, "a");
    TS_ASSERT_EQUALS(topMany.size(), 3u);
}

#endif
