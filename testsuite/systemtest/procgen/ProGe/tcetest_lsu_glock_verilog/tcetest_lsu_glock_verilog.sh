#!/bin/bash
### TCE TESTCASE
### title: The legacy LSU keeps load results correct across glock stalls

# Unit test of fu_ldh_ldhu_ldq_ldqu_ldw_sth_stq_stw_always_3 (mixed_hdl.hdb,
# verilog/lsu.v). The testbench plays the core: random word stores and loads,
# random global-lock spans of 1..16 cycles, each load result read a fixed
# number of unlocked cycles after the op was accepted and checked against a
# reference model. The data memory is stalled by glock like every other unit.
# Before the fix, the LSU's result pipeline advanced while locked and loads
# returned wrong data. Prints nothing when every load is correct.

LSU=../../../../../openasip/hdb/mixed_hdl/verilog/lsu.v
if [ ! -f "$LSU" ]; then
    LSU=$(dirname "$(dirname "$(which ttasim)")")/share/openasip/hdb/mixed_hdl/verilog/lsu.v
fi

IVERILOG=$(which iverilog 2> /dev/null)
[ "x${IVERILOG}" != "x" ] || exit 0

B=lsu_tb.vvp
rm -f $B
iverilog -g2012 -o $B ./data/lsu_unit_tb.v "$LSU" > iverilog.log 2>&1 \
    || { echo "iverilog failed"; cat iverilog.log; }
for seed in 1 2 3; do
    for stall in 0 1; do
        r=$(vvp -n $B +STALL=$stall +SEED=$seed +OPS=4000 | grep -E '^(PASS|FAIL)')
        case "$r" in PASS*) ;; *) echo "seed $seed stall $stall: $r" ;; esac
    done
done
rm -f $B iverilog.log
exit 0
