#!/bin/bash
### TCE TESTCASE
### title: memcpy, memmove and memset in non-default address spaces access the right memory
### xstdout: 104004\n328543\n1240\n964519229\n0\n\n104004\n328543\n1240\n964519229\n0\n\n104004\n328543\n1240\n964519229\n0\n\n104004\n328543\n1240\n964519229\n0\n

ADF=data/multi_addrspace.adf
SRC=data/as_mem_intrinsics.c
TPEF=$(mktemp tmpXXXXXX.tpef)

set -e
set -u
for opt in -O0 -O1 -O2 -O3; do
    tcecc -a $ADF $opt $SRC -o $TPEF
    ttasim -a $ADF -p $TPEF --no-debugmode
done

rm -f $TPEF
