#!/bin/bash
### TCE TESTCASE
### title: Tests if the same .adf file produces different
###        HDL code on different runs (nondeterministic behaviour)

# ⚠ WHAT THIS TEST CAN AND CANNOT CATCH — measured 2026-08-29, read before
#   trusting a green.
#
# It used to run generateprocessor TWICE and diff. Two draws is ~0 power against
# any low-rate nondeterminism, so it reported coverage it did not have. Worse,
# the two runs used DIFFERENT flags (`-i` vs `-t -i`) and then filtered the
# resulting differences back out (tb/ghdl/modsim) -- a comparison of two things
# that were never meant to be equal. Both are fixed: N runs, identical flags.
#
# ⛔ AND IT COULD NOT HAVE CAUGHT THE 2026-08-29 DEFECT, WHICH IT IS NAMED FOR.
#   That defect was an uninitialised `generateBusEnable_` read during emission,
#   and readParameters() assigns it on the branch taken when bus tracing is OFF.
#   THIS IDF SETS NO bustrace PARAMETER, so the flag was always initialised here
#   and the bug was impossible in this fixture by construction.
#   Measured, rather than reasoned: 0 variants in 20,000 unpatched runs, and
#   0 in 2,000 more with bustrace forced ON -- exposure alone is not enough, the
#   heap churn that makes the indeterminate byte actually differ comes from a
#   large HDB this design does not load.
#
# ⇒ For that configuration the instrument is `hdb-json/check-proge-determinism.sh`
#   (generatable_ops + asic_130nm_1.5V.hdb, measured 13-46% unpatched, and proven
#   in BOTH directions via OPENASIP_ICDEC_PLUGIN). This test covers a different,
#   cheap corner: it is the regression net for THIS machine, whose measured rate
#   is 0 (95% upper bound 0.015% at N=20,000), so N below is chosen for cost, not
#   from a rate -- there is no rate here to size against.

testName="HDL_output_nondeterministic"
dataDir="./data/HDL_output_nondeterministic"
IDF="${dataDir}/HDL_nondeterm.idf"
ADF="${dataDir}/HDL_nondeterm.adf"
PROGE="generateprocessor"
RUNS=${PROGE_DETERMINISM_RUNS:-100}

work=$(mktemp -d) || exit 1
trap 'rm -rf "$work"' EXIT

# One line is normalised: `-- Generated on <date>` in generated FU VHDL varies
# with the CLOCK, not the build. Nothing else in the tree carries a timestamp.
treehash() {
    ( cd "$1" && find . -type f | sort | while IFS= read -r f; do
        echo "== $f"
        LC_ALL=C sed 's/^-- Generated on .*/-- Generated on <N>/' "$f"
      done | md5sum | cut -d' ' -f1 )
}

first=""
for i in $(seq "$RUNS"); do
    out="${work}/p${i}"
    $PROGE -t -i "$IDF" -o "$out" "$ADF" >/dev/null 2>&1
    # ⛔ generateprocessor returns EXIT_SUCCESS on a fatal error (ProGeUI.cc
    #    swallows the exception), so gate on the ARTIFACT. Comparing two failed
    #    runs is the false green this test is supposed to be immune to.
    if [ ! -f "${out}/gcu_ic/decoder.vhdl" ] || \
       { [ ! -f "${out}/vhdl/tta0.vhdl" ] && [ ! -f "${out}/verilog/tta0.v" ]; }; then
        echo "run ${i}: generateprocessor produced no usable output tree"
        exit 1
    fi
    h=$(treehash "$out")
    if [ -z "$first" ]; then
        first=$h
    elif [ "$h" != "$first" ]; then
        echo "run ${i} of ${RUNS} differs from run 1: ${first} vs ${h}"
        echo "generateprocessor is not reproducible for ${ADF}."
        echo "Diff two output trees; the ARTEFACT names the construct. Then:"
        echo "  python3 hdb-json/check-uninitialised-members.py"
        exit 1
    fi
    rm -rf "$out"
done

exit 0
