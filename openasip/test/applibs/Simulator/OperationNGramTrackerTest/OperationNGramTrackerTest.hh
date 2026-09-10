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
 * @file OperationNGramTrackerTest.hh
 *
 * Unit tests for the counter logic in OperationNGramTracker. Exercises the
 * rolling-window and bigram / trigram accumulation via the test-only
 * constructor — these tests do not drive a real simulator, they verify the
 * n-gram math in isolation.
 */

#ifndef OPERATION_N_GRAM_TRACKER_TEST_HH
#define OPERATION_N_GRAM_TRACKER_TEST_HH

#include <TestSuite.h>

#include <string>
#include <vector>

#include "OperationNGramTracker.hh"

class OperationNGramTrackerTest : public CxxTest::TestSuite {
public:
    void testEmptyStartsAtZero();
    void testFirstOpProducesNoBigramOrTrigram();
    void testBigramAfterTwoOps();
    void testTrigramAfterThreeOps();
    void testWindowRollsAtFour();
    void testRepeatingPairDominatesBigrams();
    void testTopBigramsRanking();
    void testSeparatorAndKeyShape();
};

inline void
OperationNGramTrackerTest::testEmptyStartsAtZero() {
    OperationNGramTracker t;
    TS_ASSERT_EQUALS(t.totalOperations(), 0u);
    TS_ASSERT_EQUALS(t.totalBigrams(), 0u);
    TS_ASSERT_EQUALS(t.totalTrigrams(), 0u);
    TS_ASSERT(t.bigrams().empty());
    TS_ASSERT(t.trigrams().empty());
}

inline void
OperationNGramTrackerTest::testFirstOpProducesNoBigramOrTrigram() {
    OperationNGramTracker t;
    t.recordOperation("ADD");
    TS_ASSERT_EQUALS(t.totalOperations(), 1u);
    TS_ASSERT_EQUALS(t.totalBigrams(), 0u);
    TS_ASSERT_EQUALS(t.totalTrigrams(), 0u);
}

inline void
OperationNGramTrackerTest::testBigramAfterTwoOps() {
    OperationNGramTracker t;
    t.recordOperation("ADD");
    t.recordOperation("LDW");
    TS_ASSERT_EQUALS(t.totalOperations(), 2u);
    TS_ASSERT_EQUALS(t.totalBigrams(), 1u);
    TS_ASSERT_EQUALS(t.totalTrigrams(), 0u);
    TS_ASSERT_EQUALS(t.bigrams().at("ADD -> LDW"), 1u);
}

inline void
OperationNGramTrackerTest::testTrigramAfterThreeOps() {
    OperationNGramTracker t;
    t.recordOperation("ADD");
    t.recordOperation("LDW");
    t.recordOperation("XOR");
    TS_ASSERT_EQUALS(t.totalOperations(), 3u);
    TS_ASSERT_EQUALS(t.totalBigrams(), 2u);
    TS_ASSERT_EQUALS(t.totalTrigrams(), 1u);
    TS_ASSERT_EQUALS(t.bigrams().at("ADD -> LDW"), 1u);
    TS_ASSERT_EQUALS(t.bigrams().at("LDW -> XOR"), 1u);
    TS_ASSERT_EQUALS(t.trigrams().at("ADD -> LDW -> XOR"), 1u);
}

inline void
OperationNGramTrackerTest::testWindowRollsAtFour() {
    // After 4 ops, the rolling window should forget the first one —
    // the next trigram must be over ops #2, #3, #4, not #1, #2, #3.
    OperationNGramTracker t;
    t.recordOperation("A");
    t.recordOperation("B");
    t.recordOperation("C");
    t.recordOperation("D");
    TS_ASSERT_EQUALS(t.totalOperations(), 4u);
    TS_ASSERT_EQUALS(t.totalBigrams(), 3u);
    TS_ASSERT_EQUALS(t.totalTrigrams(), 2u);
    TS_ASSERT_EQUALS(t.trigrams().at("A -> B -> C"), 1u);
    TS_ASSERT_EQUALS(t.trigrams().at("B -> C -> D"), 1u);
}

inline void
OperationNGramTrackerTest::testRepeatingPairDominatesBigrams() {
    OperationNGramTracker t;
    // 100x the AB pattern plus one disruptor at the start.
    t.recordOperation("X");
    for (int i = 0; i < 100; ++i) {
        t.recordOperation("A");
        t.recordOperation("B");
    }
    // bigrams seen:
    //   X->A  once
    //   A->B  100 times
    //   B->A  99 times
    TS_ASSERT_EQUALS(t.bigrams().at("A -> B"), 100u);
    TS_ASSERT_EQUALS(t.bigrams().at("B -> A"), 99u);
    TS_ASSERT_EQUALS(t.bigrams().at("X -> A"), 1u);
    TS_ASSERT_EQUALS(t.totalBigrams(), 200u);
}

inline void
OperationNGramTrackerTest::testTopBigramsRanking() {
    OperationNGramTracker t;
    // Sequence A B A B A B A B A B C D C D C D E F yields bigrams:
    //   AB=5, BA=4, CD=3, DC=2, BC=1, DE=1, EF=1  (total 17).
    // Ranking is by count desc, then lexicographic asc on ties.
    for (int i = 0; i < 5; ++i) {
        t.recordOperation("A");
        t.recordOperation("B");
    }
    for (int i = 0; i < 3; ++i) {
        t.recordOperation("C");
        t.recordOperation("D");
    }
    t.recordOperation("E");
    t.recordOperation("F");

    auto top = t.topBigrams(4);
    TS_ASSERT_EQUALS(top.size(), 4u);
    TS_ASSERT_EQUALS(top[0].first,  "A -> B");
    TS_ASSERT_EQUALS(top[0].second, 5u);
    TS_ASSERT_EQUALS(top[1].first,  "B -> A");
    TS_ASSERT_EQUALS(top[1].second, 4u);
    TS_ASSERT_EQUALS(top[2].first,  "C -> D");
    TS_ASSERT_EQUALS(top[2].second, 3u);
    TS_ASSERT_EQUALS(top[3].first,  "D -> C");
    TS_ASSERT_EQUALS(top[3].second, 2u);

    // Asking for zero entries yields an empty result.
    auto topFewer = t.topBigrams(0);
    TS_ASSERT(topFewer.empty());

    // Requesting more than available returns only what's there, sorted.
    auto topMore = t.topBigrams(100);
    TS_ASSERT_EQUALS(topMore.size(), 7u);
}

inline void
OperationNGramTrackerTest::testSeparatorAndKeyShape() {
    OperationNGramTracker t;
    t.recordOperation("LD32");
    t.recordOperation("SHR1_32");
    t.recordOperation("XOR");

    // Op names can contain digits and underscores. The separator must
    // remain literally " -> " so parsers can split unambiguously.
    TS_ASSERT(t.bigrams().count("LD32 -> SHR1_32") == 1);
    TS_ASSERT(t.bigrams().count("SHR1_32 -> XOR") == 1);
    TS_ASSERT(t.trigrams().count("LD32 -> SHR1_32 -> XOR") == 1);
    TS_ASSERT_EQUALS(
        std::string(OperationNGramTracker::SEPARATOR), std::string(" -> "));
}

#endif
