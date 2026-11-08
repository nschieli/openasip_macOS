#!/bin/bash
### TCE TESTCASE
### title: Generated Verilog cores pass Verilator lint and the Yosys check

# The ASIC flows (OpenLane/LibreLane) stop on Verilator lint errors and on
# Yosys "check -assert" problems, so a generated core must pass both as is.
# Each machine is generated without bus-trace parameters, as for synthesis.
# Prints nothing when the cores are clean.

DATA=./data
MACHINES="minimal tour_custom"

leavedirty=
while getopts "d" OPTION; do
    case $OPTION in
        d) leavedirty=true ;;
        ?) exit 1 ;;
    esac
done

clear_test_data() {
    for m in $MACHINES; do rm -rf proge-$m $m.tpef ${m}*.img $m-*.log; done
    rm -f tutorial.opp tutorial.cc tutorial.opb $DATA/tutorial.opb
}
clear_test_data

# The tour machine's custom operation (REFLECT32), found by OSAL in the cwd.
cp $DATA/tutorial.opp $DATA/tutorial.cc .
buildopset tutorial > /dev/null 2>&1 || echo "buildopset failed"

VERILATOR=$(which verilator 2> /dev/null)
YOSYS=$(which yosys 2> /dev/null)

for m in $MACHINES; do
    out=proge-$m
    generateprocessor -l verilog -i $DATA/$m.idf -o $out $DATA/$m.adf \
        > $m-proge.log 2>&1 || { echo "$m: ProGe failed"; continue; }
    tcecc -O1 -a $DATA/$m.adf -o $m.tpef $DATA/main.c \
        > $m-tcecc.log 2>&1 || { echo "$m: tcecc failed"; continue; }
    generatebits -x $out -d -w 4 -p $m.tpef $DATA/$m.adf \
        > $m-pig.log 2>&1 || { echo "$m: generatebits failed"; continue; }
    files=$(find $out/verilog $out/gcu_ic -name '*.v' | sort | tr '\n' ' ')
    if [ "x$VERILATOR" != "x" ]; then
        verilator --lint-only -Wno-fatal -Wno-WIDTH -I$out/verilog \
            -I$out/gcu_ic --top-module tta0 $files > $m-verilator.log 2>&1 \
            || { echo "$m: Verilator lint errors:";
                 grep '%Error' $m-verilator.log | sed 's/:[0-9]*:[0-9]*:/:/' \
                     | sort -u; }
    fi
    if [ "x$YOSYS" != "x" ]; then
        yosys -q -p "read_verilog -sv -I$out/verilog -I$out/gcu_ic $files; \
            hierarchy -top tta0; proc; check -assert" > $m-yosys.log 2>&1 \
            || { echo "$m: Yosys check failed:";
                 grep -i 'error' $m-yosys.log | head -3; }
    fi
done

if [ "${leavedirty}" != "true" ]; then
    clear_test_data
fi
exit 0
