#!/bin/bash
### TCE TESTCASE
### title: Several cores with FUGen-generated FUs elaborate in one design

# Three cores share one --shared-files-dir: core_a and core_b from the same
# ADF, core_c from a variant whose ALU lacks shru16_32 (so its generated ALU
# differs while its LSU and RFs do not). The IDF names no RFs or FUs, so
# FUGen and RFGen generate them all. The generated FUs must land in the shared
# directory, once per distinct block, and all three cores must elaborate
# together: in one Yosys run and one iverilog compile for Verilog, and in
# one GHDL work library for VHDL. Prints nothing when all is well.

DATA=./data
SHARED=shared

leavedirty=
while getopts "d" OPTION; do
    case $OPTION in
        d) leavedirty=true ;;
        ?) exit 1 ;;
    esac
done

clear_test_data() {
    rm -rf v vhd *.tpef *.img *.log
}
clear_test_data

YOSYS=$(which yosys 2> /dev/null)
IVERILOG=$(which iverilog 2> /dev/null)
GHDL=$(which ghdl 2> /dev/null)

adf_of() {
    case $1 in
        core_c) echo $DATA/core_variant.adf ;;
        *) echo $DATA/core.adf ;;
    esac
}

for adf in core core_variant; do
    tcecc -O1 -a $DATA/$adf.adf -o $adf.tpef $DATA/main.c > tcecc.log 2>&1 \
        || { echo "tcecc failed for $adf"; exit 0; }
done

# generate <lang> <dir>
generate() {
    local lang=$1 dir=$2
    mkdir -p $dir
    for core in core_a core_b core_c; do
        local adf=$(adf_of $core)
        generateprocessor -l $lang --shared-files-dir $dir/$SHARED \
            --entity-name $core -i $DATA/core.idf -o $dir/$core $adf \
            > $dir/$core.proge.log 2>&1 \
            || { echo "ProGe failed for $core ($lang)"; return 1; }
        generatebits -e $core -x $dir/$core -d -w 4 \
            -p $(basename $adf .adf).tpef $adf > $dir/$core.pig.log 2>&1 \
            || { echo "generatebits failed for $core ($lang)"; return 1; }
    done
}

# Each distinct generated block exists once, in the shared directory only.
# check_files <dir> <lang dir> <extension> <expected counts>
# The counts are of fu_alu, fu_lsu, rf_rf and rf_bool modules.
check_files() {
    local dir=$1 sub=$2 ext=$3 expected=$4 counts=
    for core in core_a core_b core_c; do
        ls $dir/$core/$sub/fu_* $dir/$core/$sub/rf_* \
            $dir/$core/$sub/lsu_registers.* 2> /dev/null \
            | sed "s|^|unexpected per-core file: |"
    done
    for block in fu_alu fu_lsu rf_rf rf_bool; do
        counts="$counts $(ls $dir/$SHARED/$sub/${block}_*.$ext 2> /dev/null \
            | wc -l)"
    done
    [ "$counts" == " $expected" ] || echo "$sub: expected fu_alu, fu_lsu," \
        "rf_rf and rf_bool counts $expected, got$counts"
}

# --- Verilog -----------------------------------------------------------
if generate verilog v; then
    check_files v verilog v "2 1 1 1"

    sources=$(echo v/$SHARED/verilog/*.v v/core_*/verilog/*.v \
              v/core_*/gcu_ic/*.v)
    incdirs=$(for d in v/$SHARED/verilog v/core_*/verilog v/core_*/gcu_ic; do
              echo -n "-I$d "; done)
    cat > v/system.v <<EOF
module system;
  core_a a();
  core_b b();
  core_c c();
endmodule
EOF
    if [ "x${YOSYS}" != "x" ]; then
        echo "read_verilog -sv $incdirs $sources v/system.v" > v/system.ys
        echo "hierarchy -check -top system" >> v/system.ys
        $YOSYS -q -l v/yosys.log -s v/system.ys > /dev/null 2>&1 \
            || { echo "Yosys failed to elaborate the three cores:";
                 grep -m3 ERROR v/yosys.log; }
    fi
    if [ "x${IVERILOG}" != "x" ]; then
        $IVERILOG -g2012 $incdirs -s system -o v/system.vvp \
            $sources v/system.v > v/iverilog.log 2>&1 \
            || { echo "iverilog failed to compile the three cores:";
                 head -3 v/iverilog.log; }
    fi
fi

# --- VHDL --------------------------------------------------------------
if generate vhdl vhd; then
    # The VHDL flow takes its LSU from the HDB, so only the ALU is generated.
    check_files vhd vhdl vhd "2 0 1 1"

    if [ "x${GHDL}" != "x" ]; then
        (
            cd vhd && mkdir -p work &&
            ghdl_a() { ghdl -i --std=08 -fsynopsys --workdir=work "$@"; } &&
            ghdl_a $SHARED/vhdl/*.vhd* core_*/vhdl/*.vhd* \
                core_*/gcu_ic/*.vhd* &&
            for core in core_a core_b core_c; do
                ghdl -m --std=08 -fsynopsys --workdir=work $core || exit 1
            done
        ) > vhd/ghdl.log 2>&1 \
            || { echo "GHDL failed to elaborate the three cores:";
                 grep -m3 -i error vhd/ghdl.log; }
    fi
fi

if [ "${leavedirty}" != "true" ]; then
    clear_test_data
fi
exit 0
