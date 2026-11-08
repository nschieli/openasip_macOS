#!/bin/bash
### TCE TESTCASE
### title: ProGe -t exits 1 when the test bench cannot be generated, and 0 with a test bench otherwise
### xstdout: normal machine: 0, test bench: yes\nthree LSUs on one address space: 1, test bench: no

DATA=../tcetest_bustrace_verilog/data
ADF=$DATA/bustrace.adf
IDF=$DATA/bustrace-verilog.idf
OUT=proge-output

rm -rf $OUT base.adf base.idf lsu3.adf lsu3.idf
# The machine without its custom unit (its RTL is not in this data set), and
# a copy with two more load/store units on the same address space: the
# generated test bench supports at most two.
python3 - $ADF $IDF <<'PY'
import copy, sys, xml.etree.ElementTree as ET
t = ET.parse(sys.argv[1]); m = t.getroot()
for f in [f for f in m.findall('function-unit') if f.get('name') == 'VALGEN']:
    for p in f.findall('port'):
        for c in p.findall('connects-to'):
            for s in [s for s in m.findall('socket') if s.get('name') == c.text]:
                m.remove(s)
    m.remove(f)
t.write('base.adf')
i = ET.parse(sys.argv[2]); r = i.getroot()
for e in [e for e in r.findall('fu') if e.get('name') == 'VALGEN']:
    r.remove(e)
i.write('base.idf')
lsu = [f for f in m.findall('function-unit') if f.get('name') == 'LSU'][0]
sockets = {s.get('name'): s for s in m.findall('socket')}
for n in (2, 3):
    f = copy.deepcopy(lsu); f.set('name', 'LSU%d' % n)
    for p in f.findall('port'):
        c = p.find('connects-to')
        if c is not None:
            s = copy.deepcopy(sockets[c.text]); s.set('name', '%s_%d' % (c.text, n))
            m.insert(list(m).index(sockets[c.text]) + 1, s); c.text = s.get('name')
    m.insert(list(m).index(lsu) + 1, f)
t.write('lsu3.adf')
fu = [e for e in r.findall('fu') if e.get('name') == 'LSU'][0]
for n in (2, 3):   # <fu> entries must precede <rf> entries (IDF schema)
    e = copy.deepcopy(fu); e.set('name', 'LSU%d' % n)
    r.insert(list(r).index(r.findall('fu')[-1]) + 1, e)
i.write('lsu3.idf')
PY
generateprocessor -l verilog -t -i base.idf -o $OUT base.adf > /dev/null 2>&1
status=$?
tb=no; [ -d $OUT/tb ] && tb=yes
echo "normal machine: $status, test bench: $tb"
rm -rf $OUT

generateprocessor -l verilog -t -i lsu3.idf -o $OUT lsu3.adf > /dev/null 2>&1
status=$?
tb=no; [ -d $OUT/tb ] && tb=yes
echo "three LSUs on one address space: $status, test bench: $tb"
rm -rf $OUT base.adf base.idf lsu3.adf lsu3.idf
