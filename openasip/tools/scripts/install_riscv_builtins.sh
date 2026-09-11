#!/bin/bash
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
#
# Build the compiler-rt builtins for riscv32 and install them as the compiler
# runtime for oacc-riscv.
#
# Usage: ./install_riscv_builtins.sh [<compiler_rt_builtins_dir>] <install_prefix>
#
# WHY THIS EXISTS
#
# RV32IM has no FPU and no 64-bit ALU, so clang lowers float math and 64-bit
# division into calls to compiler-runtime helpers (__mulsf3, __divdi3, ...).
# The RISC-V GNU toolchain supplies those in libgcc. Without it — see
# oacc-riscv's RISCV_TOOL_PREFIX comment — they come from LLVM's compiler-rt
# builtins instead, which is what this script builds.
#
# The builtins are compiled with oacc-riscv itself (clang front end + llc with
# the OpenASIP RISC-V target plugin), the same way the RISC-V newlib is built.
# A plain `clang -target riscv32` cannot do it: this LLVM is built with
# LLVM_TARGETS_TO_BUILD="X86;host", so RISC-V exists only in the plugin.
#
# The sources live in the LLVM source tree that install_llvm_22.sh checked out
# (.../release_22/compiler-rt/lib/builtins), which is a gitignored build
# artifact and so is ABSENT in a fresh clone or a git worktree. It is resolved
# from, in order:
#   - $OPENASIP_COMPILER_RT_BUILTINS
#   - the first argument, if two arguments are given
#   - the usual build-tree locations under the repo
# If none of those find it, this script FAILS rather than installing nothing.

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OPENASIP_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
REPO_ROOT="$(cd "$OPENASIP_DIR/.." && pwd)"

if [ $# -eq 1 ]; then
    BUILTINS_SRC=""
    PREFIX="$1"
elif [ $# -eq 2 ]; then
    BUILTINS_SRC="$1"
    PREFIX="$2"
else
    echo "Usage: $0 [<compiler_rt_builtins_dir>] <install_prefix>"
    exit 1
fi

if [ -z "$BUILTINS_SRC" ]; then
    if [ -n "${OPENASIP_COMPILER_RT_BUILTINS:-}" ]; then
        BUILTINS_SRC="$OPENASIP_COMPILER_RT_BUILTINS"
    fi
fi

if [ -z "$BUILTINS_SRC" ] || [ ! -f "$BUILTINS_SRC/divdi3.c" ]; then
    for d in "$OPENASIP_DIR"/tools/scripts/llvm-build-Release/release_22/compiler-rt/lib/builtins \
             "$OPENASIP_DIR"/llvm-build-Release/release_22/compiler-rt/lib/builtins \
             "$REPO_ROOT"/llvm-build-Release/release_22/compiler-rt/lib/builtins; do
        if [ -f "$d/divdi3.c" ]; then BUILTINS_SRC="$d"; break; fi
    done
fi

if [ -z "$BUILTINS_SRC" ] || [ ! -f "$BUILTINS_SRC/divdi3.c" ]; then
    echo "ERROR: Could not locate the compiler-rt builtins sources."
    echo "  \$OPENASIP_COMPILER_RT_BUILTINS is unset or does not lead to one,"
    echo "  and no compiler-rt/lib/builtins exists under $REPO_ROOT."
    echo ""
    echo "  That tree is a gitignored LLVM build artifact, so this is expected in a"
    echo "  fresh clone or a git worktree. Either source the repo's tce-env.sh, build"
    echo "  LLVM 22 here (tools/scripts/install_llvm_22.sh <prefix>), or pass the"
    echo "  directory explicitly:"
    echo "      $0 <compiler_rt_builtins_dir> <install_prefix>"
    exit 1
fi

OACC_RISCV="$(command -v oacc-riscv || echo "$OPENASIP_DIR/src/bintools/Compiler/oacc-riscv")"
if [ ! -x "$OACC_RISCV" ]; then
    echo "ERROR: oacc-riscv not found. Install OpenASIP first, or source tce-env.sh."
    exit 1
fi

ADF="${OA_RISCV_ADF:-$PREFIX/share/openasip/data/mach/rv32im.adf}"
if [ ! -f "$ADF" ]; then
    echo "ERROR: RISC-V ADF not found: $ADF"
    echo "  Set OA_RISCV_ADF to choose another one."
    exit 1
fi

DEST_DIR="$PREFIX/riscv/lib"
DEST="$DEST_DIR/libclang_rt.builtins-riscv32.a"

# Sources that CANNOT apply to a 32-bit RISC-V baremetal target. Upstream's
# cmake excludes the same set; listing them here (with the reason) keeps a NEW
# failure visible instead of silently dropping a helper the linker will later
# ask for.
#   x87 80-bit long double (xf) — x86 only
#   atomic / emutls / enable_execute_stack — need an OS and threads
SKIP="atomic divxc3 emutls enable_execute_stack extendhfxf2 fixunsxfdi \
fixunsxfsi fixxfdi floatdixf floatundixf mulxc3 powixf2 truncxfhf2"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/oarvbuiltins.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

echo "=== Building compiler-rt builtins for riscv32 ==="
echo "sources: $BUILTINS_SRC"
echo "ADF:     $ADF"
echo "install: $DEST"
echo ""

# OpenASIP's own additions to the runtime. compiler-rt cannot supply quad-float
# helpers on a 32-bit target (CRT_HAS_TF_MODE needs a native __int128), but the
# RISC-V ABI makes long double a binary128 and newlib's vfprintf truncates one
# to double — so without this, ANY program that calls printf fails to link.
OA_RUNTIME_DIR="$OPENASIP_DIR/data/riscv/runtime"
if [ ! -f "$OA_RUNTIME_DIR/trunctfdf2.c" ]; then
    # Installed layout.
    OA_RUNTIME_DIR="$PREFIX/share/openasip/data/riscv/runtime"
fi
if [ ! -f "$OA_RUNTIME_DIR/trunctfdf2.c" ]; then
    echo "ERROR: OpenASIP RISC-V runtime sources not found (trunctfdf2.c)."
    echo "  Looked in $OPENASIP_DIR/data/riscv/runtime and"
    echo "  $PREFIX/share/openasip/data/riscv/runtime."
    exit 1
fi

skipped=0
built=0
failed=""
for src in "$BUILTINS_SRC"/*.c "$BUILTINS_SRC"/riscv/fp_mode.c "$OA_RUNTIME_DIR"/*.c; do
    [ -f "$src" ] || continue
    name="$(basename "$src" .c)"
    case " $SKIP " in
        *" $name "*) skipped=$((skipped + 1)); continue ;;
    esac
    if "$OACC_RISCV" -c -O2 -a "$ADF" -I "$BUILTINS_SRC" \
            -o "$WORK/$name.o" "$src" > "$WORK/$name.log" 2>&1; then
        built=$((built + 1))
    else
        failed="$failed $name"
    fi
done

if [ -n "$failed" ]; then
    echo "ERROR: builtins failed to compile:$failed"
    echo "  (first error of each is in $WORK, which this script is about to remove;"
    echo "   re-run with OA_KEEP_WORK=1 to keep it)"
    if [ -n "${OA_KEEP_WORK:-}" ]; then trap - EXIT; echo "  kept: $WORK"; fi
    echo "  If one of these genuinely cannot apply to riscv32, add it to SKIP in $0"
    echo "  WITH THE REASON — do not let it fail silently."
    exit 1
fi

AR="$(command -v llvm-ar || echo ar)"
RANLIB="$(command -v llvm-ranlib || echo ranlib)"
mkdir -p "$DEST_DIR"
rm -f "$DEST"
"$AR" rcs "$DEST" "$WORK"/*.o
"$RANLIB" "$DEST"

# Verify: the helpers a 32-bit target actually calls must be in there.
missing=""
for sym in __divdi3 __moddi3 __udivdi3 __mulsf3 __divsf3 __adddf3 __muldf3 \
           __trunctfdf2; do
    if ! "$(command -v llvm-nm || echo nm)" "$DEST" 2>/dev/null | grep -q " T $sym$"; then
        missing="$missing $sym"
    fi
done
if [ -n "$missing" ]; then
    echo "ERROR: the installed archive is missing:$missing"
    exit 1
fi

echo "  compiled $built objects ($skipped not applicable to riscv32)"
echo "  installed $DEST"
echo ""
echo "=== RISC-V compiler runtime installed ==="
echo "oacc-riscv now links float and 64-bit code without the RISC-V GNU toolchain."
