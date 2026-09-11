#!/bin/bash
### TCE TESTCASE
### title: Test stdlib with RISCV

rm -rf proge-output

ADF=../../../../openasip/data/mach/rv32im.adf
OACC_RISCV=../../../../openasip/src/bintools/Compiler/oacc-riscv
generateprocessor --hdb-list=generate_base32.hdb,asic_130nm_1.5V.hdb,generate_lsu_32.hdb -t $ADF &>/dev/null || exit 1
generatebits -x proge-output $ADF &>/dev/null

# Is there a way to LINK a RISC-V program? The RISC-V GNU toolchain is one.
# oacc-riscv can also link with ld.lld plus the compiler-rt builtins installed
# by tools/scripts/install_riscv_builtins.sh, so probing only for the GNU
# binary skipped this test — silently, with exit 0 — on every platform that
# uses the second route.
RISCV_GCC=$(command -v "${OA_RISCV_TOOL_PREFIX:-riscv32-unknown-elf-}gcc" 2> /dev/null)
RISCV_BUILTINS="$(tce-config --prefix 2> /dev/null)/riscv/lib/libclang_rt.builtins-riscv32.a"
if [ "x$RISCV_GCC" == "x" ] \
   && ! { command -v ld.lld > /dev/null 2>&1 && [ -f "$RISCV_BUILTINS" ]; }
then
    exit 0
fi

ghdl_bin=$(which ghdl 2> /dev/null)
if [ "x${ghdl_bin}" == "x" ]; then
    exit 0
fi

$OACC_RISCV --adf $ADF --output-format=bin -o proge-output/tb/imem_init.img data/stdlibTest.c
cp proge-output/tb/imem_init.img proge-output/tb/dmem_data_init.img || exit 1
cd proge-output
./ghdl_compile.sh &>/dev/null || exit "Ghdl compile failed"
./ghdl_simulate.sh -r 420000 &>/dev/null

cd ..

GOLDEN_TRACE=data/stdlib_trace.txt
RTL_TRACE=proge-output/hdl_sim_stdout.txt

DIFF_FILE=diff.txt

# A simulation that produced NOTHING must not pass. Without this check, diff
# writes its complaint to stderr, leaves DIFF_FILE empty, `wc -l` reports 0, the
# "> 0" test below is false, and a run that simulated nothing is recorded as a
# pass (LINUX_CERTIFICATION.md §3.2 — it mis-read a run that way).
if [ ! -s "${RTL_TRACE}" ]; then
    echo "STDLIB TEST FAILED: no RTL trace at ${RTL_TRACE}"
    exit 1
fi

diff -ar ${GOLDEN_TRACE} ${RTL_TRACE} > $DIFF_FILE

if [ ! -f "$DIFF_FILE" ]; then
    echo STDLIB TEST FAILED
    exit 1;
fi

if [ $(wc -l < "${DIFF_FILE}") -gt 0 ]; then
    echo STDLIB TEST FAILED
    exit 1;
fi
rm -rf proge-output
rm $DIFF_FILE
exit 0;
