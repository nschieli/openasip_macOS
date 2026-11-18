#!/bin/bash
### TCE TESTCASE
### title: Side-effecting operations pinned to one of two FU instances keep their order
### xstdout: 77777777\n88888888\n\n77777777\n88888888\n\n77777777\n88888888\n\n77777777\n88888888\n

ADF=data/fu_state_order.adf
SRC=data/fu_state_order.c
TPEF=$(mktemp tmpXXXXXX.tpef)

set -e
set -u
buildopset data/fu_state_order
for opt in -O0 -O1 -O2 -O3; do
    tcecc -a $ADF $opt $SRC -o $TPEF
    ttasim -a $ADF -p $TPEF --no-debugmode
done

rm -f $TPEF data/fu_state_order.opb
