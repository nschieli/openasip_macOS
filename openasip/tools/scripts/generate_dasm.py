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
generate_dasm.py — produce a normalised debug-daemon disassembly sidecar.

Reads `tcedisasm -F -n -s <adf> <tpef>` output and emits one line per
instruction in the locked sidecar format:

    0xPPPP\\t<asm>

where `PPPP` is the program counter as lowercase hex (zero-padded to a
minimum of 4 nibbles) and `<asm>` is the verbatim tcedisasm slot trace
for that instruction with the trailing `;\\t# @<pc>` PC-trailer stripped.

This is the on-disk contract consumed by openasip-debug-daemon's
`disassemble` JSON-RPC method (see PROTOCOL.md §"Sidecar formats"). The
daemon never parses raw tcedisasm output — it parses this normalised
form, so the column convention is the only thing the daemon owns.

Format properties (load-bearing — DO NOT drift without bumping
PROTOCOL.md §"Sidecar formats"):

  - One PC per line, ascending PC order.
  - PC field: `0x` prefix + lowercase hex, minimum 4 nibbles (`0x0009`).
    Wider PCs ride out naturally (`0x10042` etc.) — the daemon parses
    `0x` + arbitrary-length hex.
  - Separator: a single TAB character.
  - Asm field: tcedisasm verbatim line (all bus slots preserved,
    including no-op `...` placeholders) minus the trailing `;\\t# @<pc>`
    PC trailer. Internal commas, semicolons, whitespace preserved.
  - Trailing newline on every line, including the last.

CLI:

    generate_dasm.py <adf> <tpef> [--out PATH] [--tcedisasm PATH]

`--out -` (or omitted) writes to stdout; otherwise writes to PATH.
`--tcedisasm` overrides the binary location (default: PATH lookup).

Exit codes:
    0  — sidecar emitted, ≥1 line.
    1  — tcedisasm invocation failed (not found, exec failed, non-zero).
    2  — bad CLI arguments (missing inputs).
    3  — tcedisasm produced no PC-trailered lines (likely a tcedisasm
         output-format change; rev this script's regex rather than
         emit a silently-empty sidecar).
"""

import argparse
import os
import re
import shutil
import subprocess
import sys

# tcedisasm `-F -n -s` emits one line per instruction. The PC-trailer is
# `;\t# @<decimal-pc>` in current tcedisasm; tolerate any whitespace
# around the separator characters in case the output spacing drifts.
_PC_TRAILER = re.compile(r'\s*;\s*#\s*@(\d+)\s*$')


def main(argv):
    ap = argparse.ArgumentParser(
        prog='generate_dasm.py',
        description=(
            'Produce a normalised .dasm sidecar (PC→asm-line) from an '
            'ADF + TPEF, for openasip-debug-daemon disassemble lookups.'))
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
            'generate_dasm.py: tcedisasm not found '
            '(checked PATH and --tcedisasm)\n')
        return 1

    for label, p in (('adf', args.adf), ('tpef', args.tpef)):
        if not os.path.isfile(p):
            sys.stderr.write(f'generate_dasm.py: {label} not a file: {p}\n')
            return 2

    try:
        proc = subprocess.run(
            [tcedisasm, '-F', '-n', '-s', args.adf, args.tpef],
            capture_output=True, text=True, check=False)
    except OSError as e:
        sys.stderr.write(f'generate_dasm.py: tcedisasm exec failed: {e}\n')
        return 1
    if proc.returncode != 0:
        tail = (proc.stderr or '').strip()[-400:]
        sys.stderr.write(
            f'generate_dasm.py: tcedisasm exit={proc.returncode}\n'
            f'  stderr (tail): {tail}\n')
        return 1

    parsed = []  # list of (pc:int, asm:str)
    for raw in proc.stdout.splitlines():
        m = _PC_TRAILER.search(raw)
        if not m:
            # Non-instruction noise (blank line, banner, etc.). Skip.
            continue
        pc = int(m.group(1))
        asm = raw[:m.start()].rstrip()
        parsed.append((pc, asm))

    if not parsed:
        sys.stderr.write(
            'generate_dasm.py: zero PC-trailered lines parsed from '
            'tcedisasm output (tcedisasm format change?). Refusing to '
            'emit an empty sidecar — investigate before regenerating.\n')
        return 3

    # tcedisasm already emits in PC order, but the sidecar contract is
    # "ascending PC", so make it true here defensively.
    parsed.sort(key=lambda kv: kv[0])

    out_lines = [f'0x{pc:04x}\t{asm}\n' for pc, asm in parsed]

    if args.out == '-':
        sys.stdout.writelines(out_lines)
    else:
        out_dir = os.path.dirname(os.path.abspath(args.out))
        if out_dir and not os.path.isdir(out_dir):
            sys.stderr.write(
                f'generate_dasm.py: output directory missing: {out_dir}\n')
            return 2
        with open(args.out, 'w') as f:
            f.writelines(out_lines)

    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
