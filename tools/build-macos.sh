#!/usr/bin/env bash
#
# build-macos.sh — configure, build and check OpenASIP on macOS.
#
# ⛔⛔ CI CALLS THIS SCRIPT, AND SO DO YOU. That is the entire point. macOS CI
#     now runs only on tags and manual dispatch (dc6ae3d, after 863 billed
#     minutes in three weeks), so the everyday signal is a LOCAL build — and a
#     local build that configures differently from the release build is not a
#     signal at all, it is a second opinion about a different program.
# ⚠ THE FAILURE THIS PREVENTS IS NOT HYPOTHETICAL. The GUI was missing from
#   every macOS release because configure's wx test ran without -std; the flag
#   lived only in the workflow, so nobody building by hand could reproduce what
#   CI did, and nobody running CI could see what a developer got. One script,
#   one set of flags, both places.
#
# Usage:
#   tools/build-macos.sh                 # configure + build + install + check
#   tools/build-macos.sh --check-only    # just report on an existing prefix
#
#   OA_PREFIX      where to install            (default: ./local)
#   OA_LLVM_PREFIX an existing patched LLVM    (default: $OA_PREFIX, else ~/projects/local)
#   OA_JOBS        parallelism                 (default: all cores)
set -uo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"
OA_PREFIX="${OA_PREFIX:-$HERE/local}"
OA_JOBS="${OA_JOBS:-$(sysctl -n hw.ncpu)}"
CHECK_ONLY=0
[ "${1:-}" = "--check-only" ] && CHECK_ONLY=1

# ⚠ LLVM IS THE EXPENSIVE HALF AND IT IS REUSABLE. CI caches it; locally we
#   point at one that already exists rather than spending hours rebuilding a
#   dependency that changes a few times a year.
if [ -z "${OA_LLVM_PREFIX:-}" ]; then
    if [ -x "$OA_PREFIX/bin/llvmtce-config" ]; then OA_LLVM_PREFIX="$OA_PREFIX"
    elif [ -x "$HOME/projects/local/bin/llvmtce-config" ]; then OA_LLVM_PREFIX="$HOME/projects/local"
    fi
fi

say()  { printf '\n══ %s\n' "$*"; }
ok()   { printf '  ok   %s\n' "$*"; }
bad()  { printf '  ⛔   %s\n' "$*"; FAILED=$((FAILED+1)); }
FAILED=0

if [ "$CHECK_ONLY" = 0 ]; then
    say "dependencies"
    for f in boost xerces-c wxwidgets autoconf automake libtool; do
        brew list --versions "$f" >/dev/null 2>&1 && ok "$f $(brew list --versions "$f" | awk '{print $2}')" \
                                                  || bad "$f is not installed (brew install $f)"
    done
    [ "$FAILED" -eq 0 ] || { echo; echo "⛔ install the missing dependencies first"; exit 1; }

    [ -n "${OA_LLVM_PREFIX:-}" ] && [ -x "$OA_LLVM_PREFIX/bin/llvmtce-config" ] \
        || { echo "⛔ no patched LLVM found. Set OA_LLVM_PREFIX, or build one with"
             echo "   openasip/tools/scripts/install_llvm_22.sh <prefix>  (hours)"; exit 1; }
    ok "LLVM: $OA_LLVM_PREFIX"

    say "configure"
    cd "$HERE/openasip"
    ./autogen.sh >/dev/null
    # ⛔⛔ CXXFLAGS WITH A STANDARD, OR THE GUI SILENTLY DOES NOT BUILD. configure's
    #     wx check compiles a <wx/wx.h> program with the CXXFLAGS IT HAS AT THAT
    #     MOMENT, and the project appends -std=c++11 -std=c++17 LATER. Without
    #     this, wx 3.3's defs.h raises #error "C++11 compiler is required",
    #     DO_WX_COMPILE goes false, AM_CONDITIONAL(WX) drops every GUI directory
    #     from SUBDIRS, and make SUCCEEDS having built no GUI.
    PATH="$OA_LLVM_PREFIX/bin:$PATH" ./configure \
        --prefix="$OA_PREFIX" \
        --with-boost=/opt/homebrew \
        --with-xerces=/opt/homebrew \
        CXXFLAGS="-std=c++17" || { echo "⛔ configure failed"; exit 1; }

    say "build ($OA_JOBS jobs)"
    PATH="$OA_LLVM_PREFIX/bin:$PATH" make -j"$OA_JOBS" || { echo "⛔ build failed"; exit 1; }
    PATH="$OA_LLVM_PREFIX/bin:$PATH" make install     || { echo "⛔ install failed"; exit 1; }
    cd "$HERE"
fi

# ── The verdicts, the same ones CI prints ───────────────────────────────────
say "what configure decided about wxWidgets"
if [ -f "$HERE/openasip/config.log" ]; then
    grep -a "checking if wx headers" -A1 "$HERE/openasip/config.log" | sed 's/^/     /' | head -4
fi

say "GUI tools"
# ⛔ BY LINKAGE, NOT BY NAME: a renamed tool must not slip past, and a tool that
#    exists but links no wx is not a GUI.
guis=0
for b in "$OA_PREFIX"/bin/*; do
    [ -f "$b" ] || continue
    otool -L "$b" 2>/dev/null | grep -qi 'wx' && { guis=$((guis+1)); }
done
if [ "$guis" -gt 0 ]; then ok "$guis binaries link wxWidgets (prode/osed/hdbeditor and friends)"
else bad "NO GUI tools were built — configure disabled them, see the wx verdict above"; fi

say "oa-selftest"
if [ -x "$OA_PREFIX/bin/oa-selftest" ]; then
    PATH="$OA_PREFIX/bin:$PATH" "$OA_PREFIX/bin/oa-selftest" -v 2>&1 | tail -12 | sed 's/^/     /'
else
    bad "oa-selftest is not installed"
fi

say "what the prefix needs from outside itself"
# ⚠ Homebrew references are EXPECTED here — the open-source prefix is not
#   vendored; Verdon's installer does that. This is an inventory, not a gate.
ext=$(find "$OA_PREFIX" -type f \( -perm -u+x -o -name '*.dylib' -o -name '*.so' \) 2>/dev/null \
      | while read -r f; do file -b "$f" | grep -q Mach-O && otool -L "$f" 2>/dev/null | tail -n +2; done \
      | awk '{print $1}' | grep '^/opt/' | sort -u)
[ -n "$ext" ] && printf '%s\n' "$ext" | sed 's/^/     /' || echo "     (none)"

echo
if [ "$FAILED" -eq 0 ]; then
    echo "✅ GREEN — $OA_PREFIX"
else
    echo "⛔ RED — $FAILED check(s) failed"
fi
exit "$FAILED"
