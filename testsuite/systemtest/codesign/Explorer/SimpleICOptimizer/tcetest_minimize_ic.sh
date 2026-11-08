#!/bin/sh
### TCE TESTCASE
### title: minimize-ic writes an IC-minimized machine and exits 0; fails with an error on a bad program
### xstdout: minimize-ic: 0, fewer socket connections: yes\nbad program: 1

TCE_ROOT="../../../../../openasip"
PATH="$(cd ${TCE_ROOT}/src/codesign/Explorer 2>/dev/null && pwd):$PATH"
export PATH
MINIMIZE_IC="${TCE_ROOT}/scripts/minimize-ic"
ADF=./data/bloated3xminimal.adf
OUT=minimized_tmp.adf

rm -f $OUT
sh $MINIMIZE_IC $ADF data/scheduled.tpef $OUT > /dev/null 2>&1 < /dev/null
status=$?
before=$(grep -c -e '<writes-to>' -e '<reads-from>' $ADF)
after=$(grep -c -e '<writes-to>' -e '<reads-from>' $OUT 2>/dev/null || echo $before)
fewer=no; [ "$after" -lt "$before" ] && fewer=yes
echo "minimize-ic: $status, fewer socket connections: $fewer"

sh $MINIMIZE_IC $ADF no_such_program.tpef $OUT.2 > /dev/null 2>&1 < /dev/null
echo "bad program: $?"
rm -f $OUT $OUT.2
