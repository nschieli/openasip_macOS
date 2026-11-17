#!/bin/bash
### TCE TESTCASE
### title: Empty inline asm blocks (compiler barriers) compile and run
### xstdout: 5 28 8\n\n5 28 8\n\n5 28 8\n\n5 28 8\n

ADF=data/small.adf
SRC=data/compiler_barrier.c
TPEF=$(mktemp tmpXXXXXX.tpef)

set -e
set -u
for opt in -O0 -O1 -O2 -O3; do
    tcecc -a $ADF $opt $SRC -o $TPEF
    ttasim -a $ADF -p $TPEF --no-debugmode
done

rm -f $TPEF
