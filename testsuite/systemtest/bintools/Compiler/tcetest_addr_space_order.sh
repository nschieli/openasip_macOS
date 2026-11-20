#!/bin/sh
### TCE TESTCASE
### title: TPEF address spaces in the machine's order, whatever the build path
### xstdout: instructions data data1 data2

# The data memories used to be written in the order of their AddressSpace
# pointers, i.e. heap order, so the TPEF's address-space indices (and its
# bytes) depended on the environment, e.g. on the length of the build path.
mach=data/multi_addrspace.adf
src=data/multi_addrspace.c
top=$(mktemp -d tmpXXXXXX)
baseline=""
for d in a bb ccccccc dddddddddddddddddddddddddddddddd
do
    mkdir -p $top/$d
    cp $mach $src $top/$d/
    (cd $top/$d && tcecc -O3 -a multi_addrspace.adf -o p.tpef multi_addrspace.c)
    if [ -z "$baseline" ]; then
        baseline=$top/$d/p.tpef
    else
        cmp $baseline $top/$d/p.tpef
    fi
done
# the address-space table: the instruction space (used first, by the code),
# then the data spaces in the ADF's order
dumptpef -j 1 $baseline | awk 'NF == 5 && $1 ~ /:$/ {printf "%s%s", s, $5; s = " "} END {print ""}'
rm -rf $top
