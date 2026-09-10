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
"""Generate 64-bit ALU/MUL operation HDB for OpenASIP.

Creates generate_base64.hdb with VHDL and Verilog operation snippets
for all operations needed by a 64-bit TTA machine.

Usage: python3 generate_base64.py
"""
import os
import shutil
import sqlite3

# Operation definitions: (name, vhdl_snippet, verilog_snippet)
# FUGen wraps these in an entity — op1/op2/op3/op4 are ports whose
# widths come from the ADF, not these snippets.

OPERATIONS = [
    # --- 2-input arithmetic ---
    ("add64",
     "op3 <= std_logic_vector(signed(op1) + signed(op2));",
     "op3 = $signed(op1) + $signed(op2);"),

    ("sub64",
     "op3 <= std_logic_vector(signed(op1) - signed(op2));",
     "op3 = $signed(op1) - $signed(op2);"),

    # --- 2-input logic ---
    ("and64",
     "op3 <= op1 and op2;",
     "op3 = op1 & op2;"),

    ("ior64",
     "op3 <= op1 or op2;",
     "op3 = op1 | op2;"),

    ("xor64",
     "op3 <= op1 xor op2;",
     "op3 = op1 ^ op2;"),

    # --- 2-input comparison (result is 1-bit in output port) ---
    ("eq64",
     "if op1 = op2 then\n  op3 <= (0 => '1', others => '0');\nelse\n  op3 <= (others => '0');\nend if;",
     "op3 = (op1 == op2) ? 1 : 0;"),

    ("ne64",
     "if op1 /= op2 then\n  op3 <= (0 => '1', others => '0');\nelse\n  op3 <= (others => '0');\nend if;",
     "op3 = (op1 != op2) ? 1 : 0;"),

    ("gt64",
     "if signed(op1) > signed(op2) then\n  op3 <= (0 => '1', others => '0');\nelse\n  op3 <= (others => '0');\nend if;",
     "op3 = ($signed(op1) > $signed(op2)) ? 1 : 0;"),

    ("gtu64",
     "if unsigned(op1) > unsigned(op2) then\n  op3 <= (0 => '1', others => '0');\nelse\n  op3 <= (others => '0');\nend if;",
     "op3 = (op1 > op2) ? 1 : 0;"),

    # --- 2-input shifts (6-bit shift amount for 64-bit) ---
    ("shl64",
     "op3 <= std_logic_vector(shift_left(unsigned(op1), to_integer(unsigned(op2(5 downto 0)))));",
     "op3 = op1 <<< op2;"),

    ("shr64",
     "op3 <= std_logic_vector(shift_right(signed(op1), to_integer(unsigned(op2(5 downto 0)))));",
     "op3 = $signed(op1) >>> op2;"),

    ("shru64",
     "op3 <= std_logic_vector(shift_right(unsigned(op1), to_integer(unsigned(op2(5 downto 0)))));",
     "op3 = op1 >> op2;"),

    # --- 2-input min/max ---
    ("max64",
     "if signed(op1) > signed(op2) then\n  op3 <= op1;\nelse\n  op3 <= op2;\nend if;",
     "op3 = ($signed(op1) > $signed(op2)) ? op1 : op2;"),

    ("maxu64",
     "if unsigned(op1) > unsigned(op2) then\n  op3 <= op1;\nelse\n  op3 <= op2;\nend if;",
     "op3 = (op1 > op2) ? op1 : op2;"),

    ("min64",
     "if signed(op1) > signed(op2) then\n  op3 <= op2;\nelse\n  op3 <= op1;\nend if;",
     "op3 = ($signed(op1) > $signed(op2)) ? op2 : op1;"),

    ("minu64",
     "if unsigned(op1) > unsigned(op2) then\n  op3 <= op2;\nelse\n  op3 <= op1;\nend if;",
     "op3 = (op1 > op2) ? op2 : op1;"),

    # --- 1-input ---
    ("abs64",
     "if signed(op1) < 0 then\n  op2 <= std_logic_vector(to_signed(0,op2'length) - signed(op1));\nelse\n  op2 <= op1;\nend if;",
     "if (op1[63] == 1'b1)\n    op2 = -op1;\nelse\n    op2 = op1;"),

    ("neg64",
     "op2 <= std_logic_vector(to_signed(0,op2'length) - signed(op1));",
     "op2 = -$signed(op1);"),

    # --- 1-input sign extension ---
    # sxh64: sign-extend from 16 to 64
    ("sxh64",
     "op2 <= std_logic_vector(resize(signed(op1(15 downto 0)), 64));",
     "op2 = {{48{op1[15]}}, op1[15:0]};"),

    # sxq64: sign-extend from 8 to 64
    ("sxq64",
     "op2 <= std_logic_vector(resize(signed(op1(7 downto 0)), 64));",
     "op2 = {{56{op1[7]}}, op1[7:0]};"),

    # sxw64: sign-extend from 32 to 64
    ("sxw64",
     "op2 <= std_logic_vector(resize(signed(op1(31 downto 0)), 64));",
     "op2 = {{32{op1[31]}}, op1[31:0]};"),

    # --- Shift-and-add (array indexing) ---
    ("shl1add64",
     "op3 <= std_logic_vector(shift_left(unsigned(op1), 1) + unsigned(op2));",
     "op3 = (op1 <<< 1) + op2;"),

    ("shl2add64",
     "op3 <= std_logic_vector(shift_left(unsigned(op1), 2) + unsigned(op2));",
     "op3 = (op1 <<< 2) + op2;"),

    # --- Multiply ---
    ("mul64",
     "op3 <= std_logic_vector(resize(unsigned(op1) * unsigned(op2), op3'length));",
     "op3 = op1 * op2;"),

    # --- Multiply-accumulate (3 inputs) ---
    ("mac64",
     "op4 <= std_logic_vector(resize(unsigned(op1) + unsigned(op2) * unsigned(op3), op4'length));",
     "op4 = op1 + op2*op3;"),

    # --- IO (stdout) — simulation-only character output, no-op for synthesis ---
    ("stdout",
     "null; -- simulation-only: character output (no-op for synthesis)",
     "// simulation-only: character output (no-op for synthesis)"),
]


def make_dir(path):
    os.makedirs(path, exist_ok=True)


def main():
    hdb_dir = os.path.dirname(os.path.abspath(__file__))
    hdb_path = os.path.join(hdb_dir, "generate_base64.hdb")
    snippet_dir = os.path.join(hdb_dir, "generate_base64")
    vhdl_dir = os.path.join(snippet_dir, "vhdl")
    vlog_dir = os.path.join(snippet_dir, "verilog")

    make_dir(vhdl_dir)
    make_dir(vlog_dir)

    # Start from empty HDB
    empty_hdb = os.path.join(hdb_dir, "generate_lsu", "shared", "empty.hdb")
    if os.path.exists(empty_hdb):
        shutil.copyfile(empty_hdb, hdb_path)
    else:
        # Fallback: create via createhdb if available
        import subprocess
        subprocess.run(["createhdb", hdb_path], check=True)

    hdb = sqlite3.connect(hdb_path)
    c = hdb.cursor()

    for name, vhdl_code, vlog_code in OPERATIONS:
        # Write snippet files
        vhdl_file = os.path.join(vhdl_dir, f"{name}.vhd")
        vlog_file = os.path.join(vlog_dir, f"{name}.v")

        with open(vhdl_file, "w") as f:
            f.write(vhdl_code)
        with open(vlog_file, "w") as f:
            f.write(vlog_code)

        # Relative paths from hdb/ directory (how FUGen resolves them)
        vhdl_rel = f"generate_base64/vhdl/{name}.vhd"
        vlog_rel = f"generate_base64/verilog/{name}.v"

        # Insert operation implementation
        # latency=NULL means FUGen uses the ADF pipeline definition
        c.execute(
            "INSERT INTO operation_implementation "
            "VALUES (NULL, NULL, ?, '', '', '', '', '')",
            (name,))
        op_id = c.lastrowid

        # Link VHDL source (format 0 = VHDL)
        c.execute("INSERT INTO block_source_file VALUES (NULL, ?, 0)",
                  (vhdl_rel,))
        c.execute(
            "INSERT INTO operation_implementation_source_file "
            "VALUES (NULL, ?, ?)",
            (op_id, c.lastrowid))

        # Link Verilog source (format 1 = Verilog)
        c.execute("INSERT INTO block_source_file VALUES (NULL, ?, 1)",
                  (vlog_rel,))
        c.execute(
            "INSERT INTO operation_implementation_source_file "
            "VALUES (NULL, ?, ?)",
            (op_id, c.lastrowid))

    hdb.commit()
    hdb.close()

    print(f"Created {hdb_path} with {len(OPERATIONS)} operations")
    print(f"Snippet files in {snippet_dir}/")
    for name, _, _ in OPERATIONS:
        print(f"  {name}")


if __name__ == "__main__":
    main()
