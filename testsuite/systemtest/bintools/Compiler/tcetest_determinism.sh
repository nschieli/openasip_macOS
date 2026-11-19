#!/bin/sh
### TCE TESTCASE 
### title: Ensure deterministic compilation
### xstdout:

mach=data/minimal_with_stdout.adf
src=data/hello.c
baseline=$(mktemp tmpXXXXXX)

# First check without optimizations
tcecc $src -llwpr -O0 -a $mach -o $baseline

for i in 1 2 3 4 5
do
    prog=$(mktemp tmpXXXXXX)
    tcecc $src -llwpr -O0 -a $mach -o $prog
    diff $baseline $prog
    rm $prog
done

# Next check with optimizations
tcecc $src -llwpr -O3 -a $mach -o $baseline

for i in 1 2 3 4 5
do
    prog=$(mktemp tmpXXXXXX)
    tcecc $src -llwpr -O3 -a $mach -o $prog
    diff $baseline $prog
    rm $prog
done

# Several files: the link order must be the command-line order, not the
# order in which the parallel compile jobs finish, and equal to -j 1's.
multi="data/determinism/main.c data/determinism/big.c data/determinism/small1.c data/determinism/small2.c data/determinism/small3.c"
tcecc $multi -O3 -j 1 -a $mach -o $baseline

for i in 1 2 3 4 5 6 7 8
do
    prog=$(mktemp tmpXXXXXX)
    tcecc $multi -O3 -j 5 -a $mach -o $prog
    diff $baseline $prog
    rm $prog
done

rm $baseline
# Just for the newline
echo