#!/bin/bash
### TCE TESTCASE
### title: FUGen's Verilog constant shifts (shl/shr/shruN_32) match ttasim

# The ALU and LSU are left out of the IDF, so FUGen generates them. The ALU
# has all 15 shift-by-constant operations, and the program applies each to a
# negative and a positive value. The RTL's bus trace must equal ttasim's.
# Prints nothing when they match.

DATA=./data
ADF=$DATA/shifts.adf
TPEF=shifts.tpef
PO=proge-out

leavedirty=
while getopts "d" OPTION; do
    case $OPTION in
        d) leavedirty=true ;;
        ?) exit 1 ;;
    esac
done

clear_test_data() {
    rm -rf $PO $TPEF ${TPEF}.* shifts.img shifts_data.img *.log rtl.trace sim.trace
}
clear_test_data

IVERILOG=$(which iverilog 2> /dev/null)

tcecc -O1 -a $ADF -k out,in -o $TPEF $DATA/shifts.c > tcecc.log 2>&1 \
    || { echo "tcecc failed"; exit 0; }
cycles=$(ttasim -e "setting bus_trace 1; mach $ADF; prog $TPEF; run; \
    puts [info proc cycles]; quit" < /dev/null 2>&1 | tail -1)
generateprocessor -l verilog -t -i $DATA/shifts.idf -o $PO $ADF \
    > proge.log 2>&1 || { echo "ProGe failed"; exit 0; }
generatebits -d -w 4 -p $TPEF -x $PO $ADF > pig.log 2>&1 \
    || { echo "generatebits failed"; exit 0; }
cp shifts.img $PO/tb/imem_init.img
cp shifts_data.img $PO/tb/dmem_data_init.img

if [ "x${IVERILOG}" != "x" ]; then
    period=$(sed -nE 's/.*parameter PERIOD *= *([0-9]+).*/\1/p' \
        $PO/verilog/*globals_pkg.vh | head -1)
    ( cd $PO && ./iverilog_compile.sh > ../iverilog_compile.log 2>&1 \
        && ./iverilog_simulate.sh -r $(( (cycles + 200) * ${period:-10} )) \
            > ../iverilog_simulate.log 2>&1 ) || echo "iverilog failed"
    head -n "$cycles" $PO/bus.dump > rtl.trace
    head -n "$cycles" ${TPEF}.bustrace > sim.trace
    cmp -s rtl.trace sim.trace || { echo "RTL and ttasim bus traces differ:";
        diff rtl.trace sim.trace | head -4; }
fi

if [ "${leavedirty}" != "true" ]; then
    clear_test_data
fi
exit 0
