#!/bin/bash
### TCE TESTCASE
### title: Atomic fences compile and run
### xstdout: 3 9\n\n3 9\n\n3 9\n\n3 9\n

ADF=data/small.adf
SRC=data/atomic_fence.c
TPEF=$(mktemp tmpXXXXXX.tpef)

set -e
set -u
for opt in -O0 -O1 -O2 -O3; do
    tcecc -a $ADF $opt $SRC -o $TPEF
    ttasim -a $ADF -p $TPEF --no-debugmode
done

rm -f $TPEF
