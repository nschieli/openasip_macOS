#!/bin/sh
### TCE TESTCASE
### title: oacc -k given several times keeps every symbol, like one comma-separated -k
### xstdout: a,b: 0x0005029e 0x000502cb\na -k b: 0x0005029e 0x000502cb

mach=data/minimal_with_stdout.adf
src=data/keep_symbols.c
program=$(mktemp tmpXXXXXX)

read_back() {
    ttasim -a $mach -p $program -e "run; puts \"[x /u w kept_a] [x /u w kept_b]\"; quit" < /dev/null 2>&1 | grep -v "^$"
}

oacc -O3 -a $mach -o $program -k kept_a,kept_b $src || exit 2
echo "a,b: $(read_back)"
oacc -O3 -a $mach -o $program -k kept_a -k kept_b $src || exit 2
echo "a -k b: $(read_back)"

rm -f $program
