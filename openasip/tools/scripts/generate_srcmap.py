#!/usr/bin/env python3
# Copyright (C) 2026 Nicolas Schieli.
#
# This library is free software; you can redistribute it and/or
# modify it under the terms of the GNU Lesser General Public
# License as published by the Free Software Foundation; either
# version 2.1 of the License, or (at your option) any later version.
#
# This library is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# Lesser General Public License for more details.
#
# You should have received a copy of the GNU Lesser General Public
# License along with this library; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA
# 02110-1301 USA
#
# SPDX-License-Identifier: LGPL-2.1-or-later
"""
generate_srcmap.py — produce a normalised source-line mapping sidecar.

Reads `tcedisasm -F -n -s <adf> <tpef>` output and emits one line per
DEBUG-annotated instruction in the locked sidecar format:

    0xPPPP\\t<file>\\t<line>

where `PPPP` is the program counter as lowercase hex (zero-padded to a
minimum of 4 nibbles), `<file>` is the verbatim source path emitted by
the LLVMTCEBuilder DebugLoc extraction (`ANN_DEBUG_SOURCE_CODE_PATH`),
and `<line>` is the decimal source line number
(`ANN_DEBUG_SOURCE_CODE_LINE`).

This is the on-disk contract consumed by openasip-debug-daemon's
`source_lookup` JSON-RPC method (see PROTOCOL.md §"Sidecar formats" —
.srcmap subsection). The daemon never parses raw tcedisasm output — it
parses this normalised form, so the column convention is the only thing
the daemon owns.

Format properties (load-bearing — DO NOT drift without bumping
PROTOCOL.md §"Sidecar formats"):

  - One PC per line, ascending PC order.
  - Only PCs with both `# file:` and `# slines:` annotations are
    emitted. Un-annotated instructions (startup glue, library code
    compiled without `-g`) are silently skipped — `source_lookup` for
    those PCs returns `lines: []` (out-of-range), matching the same
    semantic D6a's `disassemble` uses.
  - PC field: `0x` prefix + lowercase hex, minimum 4 nibbles
    (`0x0009`). Wider PCs ride out naturally — the daemon parses
    `0x` + arbitrary-length hex.
  - Separator: a single TAB character between each of {PC, file,
    line}; total two TABs per row.
  - File field: verbatim path from the `# file: <path>` trailer.
    No quoting, no escaping; embedded TABs / newlines are not
    expected (LLVM filename strings don't contain them in practice).
    The producer rejects rows where the file field would contain a
    literal TAB or newline (defensive — would break the column
    convention).
  - Line field: decimal integer (no leading zeros except for `0`
    itself; matches `tcedisasm`'s output).
  - Trailing newline on every line, including the last.

CLI:

    generate_srcmap.py <adf> <tpef> [--out PATH] [--tcedisasm PATH]

`--out -` (or omitted) writes to stdout; otherwise writes to PATH.
`--tcedisasm` overrides the binary location (default: PATH lookup).

Exit codes:
    0  — sidecar emitted, ≥1 annotated line.
    1  — tcedisasm invocation failed (not found, exec failed, non-zero).
    2  — bad CLI arguments (missing inputs).
    3  — tcedisasm produced PC-trailered lines but ZERO of them carry
         `# file:` / `# slines:` annotations — likely the TPEF was
         compiled without `-g`. Refusing to emit an empty sidecar.
"""

import argparse
import os
import re
import shutil
import subprocess
import sys

# tcedisasm `-F -n -s` emits one line per instruction with trailers
# in this order on annotated moves:
#     <slot-trace> ;\t# @<pc>\t# file: <path>\t# slines: <line>
#
# The `-n` flag adds the `# @<pc>` PC-trailer (always present);
# `# file:` and `# slines:` come from the LLVMTCEBuilder DebugLoc
# extraction at LLVMTCEBuilder.cc:2070-2129 and are only present
# on moves whose source MachineInstr carried a non-null DebugLoc.
_PC_TRAILER    = re.compile(r'#\s*@(\d+)')
_FILE_TRAILER  = re.compile(r'#\s*file:\s*([^\t\n]+?)(?=\t#|\s*$)')
_SLINE_TRAILER = re.compile(r'#\s*slines:\s*(\d+)')


def main(argv):
    ap = argparse.ArgumentParser(
        prog='generate_srcmap.py',
        description=(
            'Produce a normalised .srcmap sidecar (PC→file+line) from an '
            'ADF + TPEF, for openasip-debug-daemon source_lookup queries.'))
    ap.add_argument('adf', help='Path to the .adf machine description.')
    ap.add_argument('tpef', help='Path to the .tpef program binary.')
    ap.add_argument('--out', default='-',
                    help='Output sidecar path; "-" = stdout (default).')
    ap.add_argument('--tcedisasm', default=None,
                    help='Override tcedisasm binary path (default: PATH).')
    args = ap.parse_args(argv)

    tcedisasm = args.tcedisasm or shutil.which('tcedisasm')
    if not tcedisasm or not os.path.isfile(tcedisasm):
        sys.stderr.write(
            'generate_srcmap.py: tcedisasm not found '
            '(checked PATH and --tcedisasm)\n')
        return 1

    for label, p in (('adf', args.adf), ('tpef', args.tpef)):
        if not os.path.isfile(p):
            sys.stderr.write(f'generate_srcmap.py: {label} not a file: {p}\n')
            return 2

    try:
        proc = subprocess.run(
            [tcedisasm, '-F', '-n', '-s', args.adf, args.tpef],
            capture_output=True, text=True, check=False)
    except OSError as e:
        sys.stderr.write(f'generate_srcmap.py: tcedisasm exec failed: {e}\n')
        return 1
    if proc.returncode != 0:
        tail = (proc.stderr or '').strip()[-400:]
        sys.stderr.write(
            f'generate_srcmap.py: tcedisasm exit={proc.returncode}\n'
            f'  stderr (tail): {tail}\n')
        return 1

    parsed = []  # list of (pc:int, file:str, line:int)
    saw_any_pc = False
    for raw in proc.stdout.splitlines():
        m_pc = _PC_TRAILER.search(raw)
        if not m_pc:
            continue
        saw_any_pc = True
        m_file  = _FILE_TRAILER.search(raw)
        m_sline = _SLINE_TRAILER.search(raw)
        if not m_file or not m_sline:
            # Un-annotated instruction — skip per format contract.
            continue
        pc = int(m_pc.group(1))
        src_file = m_file.group(1).strip()
        if '\t' in src_file or '\n' in src_file:
            # Defensive: emitting a tab/newline-bearing path would
            # break the column convention. Skip with a stderr note.
            sys.stderr.write(
                f'generate_srcmap.py: skipping pc={pc} — file path '
                f'contains TAB or newline: {src_file!r}\n')
            continue
        line_no = int(m_sline.group(1))
        parsed.append((pc, src_file, line_no))

    if not saw_any_pc:
        sys.stderr.write(
            'generate_srcmap.py: zero PC-trailered lines parsed from '
            'tcedisasm output (tcedisasm format change?). Refusing to '
            'emit an empty sidecar — investigate before regenerating.\n')
        return 3

    if not parsed:
        sys.stderr.write(
            'generate_srcmap.py: tcedisasm output had no `# file:` / '
            '`# slines:` annotations on any instruction. Likely the '
            'TPEF was compiled without `-g`. Refusing to emit an empty '
            'sidecar.\n')
        return 3

    # tcedisasm emits in PC order, but the sidecar contract is
    # "ascending PC", so make it true here defensively.
    parsed.sort(key=lambda kv: kv[0])

    out_lines = [
        f'0x{pc:04x}\t{src_file}\t{line_no}\n'
        for pc, src_file, line_no in parsed
    ]

    if args.out == '-':
        sys.stdout.writelines(out_lines)
    else:
        out_dir = os.path.dirname(os.path.abspath(args.out))
        if out_dir and not os.path.isdir(out_dir):
            sys.stderr.write(
                f'generate_srcmap.py: output directory missing: {out_dir}\n')
            return 2
        with open(args.out, 'w') as f:
            f.writelines(out_lines)

    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
