<!--
    Copyright (C) 2026 Nicolas Schieli.

    Licensed by the copyright holder under the GNU Lesser General Public
    License, version 2.1 or (at your option) any later version, to match the
    licence of the OpenASIP project it is distributed alongside.

    This is an original work, not a modification of OpenASIP; the LGPL applies
    here by the author's choice, not by OpenASIP's LICENSE.txt.

    SPDX-License-Identifier: LGPL-2.1-or-later
-->

# Building OpenASIP on macOS (Apple Silicon)

This guide is for someone coming to this cold. It assumes no prior knowledge of
OpenASIP's build system, and it lists every prerequisite explicitly.

**Apple Silicon (`arm64`) only.** Intel Macs are not covered.

---

## 1. What you get, and what you do not

OpenASIP's command-line toolchain builds and runs natively on macOS: the
compiler driver (`oacc`), the simulator (`ttasim`), the processor generator
(`generateprocessor`) and the bitstream generator (`generatebits`).

**Both simulator engines work**: the interpretive one (the default) and the
compiled one (`ttasim -q`), which generates and compiles a simulation engine at
run time.

**The RISC-V flow is included too** — `oacc-riscv`, `riscv-tdgen`,
`tceriscvopgen` and the RISC-V newlib are all built and installed by the same
`make`. On macOS it needs **no RISC-V GNU toolchain**; see §6.

**The graphical tools are NOT built**: `ProDe` (architecture editor), `OSEd`
(operation set editor), `Proxim` (simulator GUI), and `HDBEditor`. They depend
on wxWidgets, and `configure` deliberately produces a UI-free build when
wxWidgets is absent. You will see this in the configure summary, and it is the
expected outcome, not an error:

```
wxWidgets library not found. Tools using wxWidgets cannot be build
(ProDe, OSEd, Proxim).
```

---

## 2. Prerequisites

### 2.1 Xcode Command Line Tools

```bash
xcode-select --install
```

Verified against Command Line Tools **26.6.0** (Apple clang 21.0.0).

### 2.2 Homebrew packages

```bash
brew install boost xerces-c autoconf automake libtool cmake ninja
```

| package | why it is needed |
|---|---|
| `boost` | core dependency (base, regex, system, thread) |
| `xerces-c` | XML parsing (machine descriptions, operation sets) |
| `autoconf`, `automake`, `libtool` | `configure` is not shipped; you must generate it |
| `cmake` | required to build LLVM (step 3) |
| `ninja` | optional; the LLVM script uses Unix Makefiles |

**Optional — only if you want the graphical tools** (`prode`, `proxim`, `osed`,
`hdbeditor`):

```bash
brew install wxwidgets graphviz
```

| package | why it is needed |
|---|---|
| `wxwidgets` | the four GUIs. **3.3.x is fine** — `configure` accepts `3.3.*`, and the tree needs no source changes to build against it. Without wx, `configure` simply leaves the GUIs out; that is a first-class supported configuration |
| `graphviz` | **`osed` only**, and only for the DAG view: it renders operation DAGs by shelling out to `dot`. Without it, `osed` still runs and still edits DAG *source* — it warns once and hides the rendered pane. Nothing else in the toolchain uses `dot` |

### 2.3 Do NOT install these

macOS already provides working versions, and `configure` picks them up by
itself. Each was verified unnecessary by installing it, removing it, and
confirming `configure` still succeeds:

| do not install | macOS provides |
|---|---|
| `make` | Apple's `/usr/bin/make` (GNU Make 3.81) is sufficient |
| `libedit` | the system libedit satisfies the `histedit.h` probe |
| `tcl-tk` | `configure` selects the system Tcl (8.5) regardless |
| `wxWidgets` | intentionally omitted — see §1 |

> **Note on Homebrew's `libtool`.** It installs the tool as **`glibtoolize`**,
> not `libtoolize`. `autogen.sh` detects this automatically and prints a warning
> suggesting a `sudo ln -s`. **That symlink is not needed** — ignore the
> suggestion.

---

## 3. Build LLVM

OpenASIP requires a patched LLVM/Clang, built from source. **This is the long
step** — roughly 30 minutes on a 10-core Apple Silicon machine, and it needs a
few GB of disk. Start it first.

```bash
cd openasip
./tools/scripts/install_llvm_22.sh ~/projects/local
```

Run it from `openasip/`. The script builds into `./llvm-build-Release` relative
to the current directory, and the compiler looks for the libc++ headers under
`openasip/llvm-build-Release`.

This clones the patched LLVM, builds it, installs it into the prefix you gave,
and generates `tce-env.sh` at the repository root.

> The LLVM fork installs `llvm-config` under the name **`llvmtce-config`**.
> That is expected; `configure` looks for it by that name.

---

## 4. Build OpenASIP

```bash
source tce-env.sh          # from the repository root; sets PATH and DYLD_LIBRARY_PATH

cd openasip
./autogen.sh               # generates `configure`, which is not in the repository
./configure --prefix=$HOME/projects/local \
            --with-boost=/opt/homebrew \
            --with-xerces=/opt/homebrew
make -j$(sysctl -n hw.ncpu)
make install
```

### Why the two `--with-` switches are required

Homebrew installs into `/opt/homebrew`, which is **not** on clang's default
search path, so `configure` cannot find boost or xerces without being told.

Passing `CPPFLAGS=-I/opt/homebrew/include` instead **does not work** for boost.
The `AX_BOOST_BASE` macro then concludes boost is a system install, leaves
`BOOST_LDFLAGS` empty, and `configure` rejects that with the confusing message
`boost library not found. Install it or use --with-boost switch`. Use the
switch.

---

## 5. Verify

```bash
oa-selftest -v
```

This takes a while — up to a couple of hours — because it compiles and simulates
several programs.

A quick end-to-end smoke test is much faster:

```bash
cat > hello.c <<'EOF'
#include <stdio.h>
int main() { printf("hello\n"); return 0; }
EOF

MACH=$HOME/projects/local/share/openasip/data/mach/minimal_with_stdout.adf
oacc --swfp -a $MACH -O0 -o hello.tpef hello.c
ttasim -a $MACH -p hello.tpef --no-debugmode      # prints: hello
```

> `--swfp` selects software floating-point emulation. `minimal.adf` has no
> floating-point unit, and `printf` needs float comparison, so without it you
> get `emulation function for footprint 'i1.fcmp.olt.f32.f32' wasn't found`.
> Use `minimal_with_stdout.adf` rather than `minimal.adf`, which has no output
> unit at all.

**The first compile of any program is slow** (minutes). `oacc` builds an
LLVM backend plugin for your specific target architecture and caches it under
`~/.cache/openasip`. Later compiles for the same architecture reuse the cache.
The cache key includes OpenASIP's version string, so the first compile after
**any rebuild** pays that cost again — this is the usual explanation for a
suddenly "slow" toolchain.

### RISC-V smoke test

```bash
RV=$HOME/projects/local/share/openasip/data/mach/rv32im.adf
printf 'int main(){return 0;}\n' > rv.c
oacc-riscv -O2 -a $RV -o rv.elf rv.c        # -> ELF 32-bit LSB executable, UCB RISC-V
```

See §6 for what is needed before RISC-V programs that use `printf` or floating
point will link.

---

## 6. RISC-V on macOS

The RISC-V flow works **without the RISC-V GNU toolchain**
(`tools/scripts/install_riscv_tools.sh`, which builds `riscv-gnu-toolchain` and
`elf2hex` from source). Everything it provided has an equivalent in the LLVM you
already built: `llvm-mc` with OpenASIP's RISC-V target plugin assembles,
`ld.lld` links, and `llvm-objcopy` produces memory images. **If the GNU
toolchain is installed, it is used instead**, so nothing changes on platforms
that have it.

One step is needed before RISC-V programs that use `printf` or floating point
will link — the compiler runtime that would otherwise come from `libgcc`:

```bash
openasip/tools/scripts/install_riscv_builtins.sh ~/projects/local
```

It compiles LLVM's compiler-rt builtins for riscv32 (about two minutes) and
installs them next to the RISC-V newlib. Without it, integer-only programs link
fine and anything else fails with `undefined symbol: __divdi3` or
`__trunctfdf2`.

> **Why `printf` needs this.** The RISC-V ABI makes `long double` a 128-bit
> quad, and newlib's `vfprintf` truncates one to `double` even when long-double
> output is disabled — so every program calling `printf` needs `__trunctfdf2`.
> compiler-rt cannot supply it on any 32-bit target (its quad support requires a
> native `__int128`), so OpenASIP ships its own at
> `data/riscv/runtime/trunctfdf2.c`.

If your toolchain uses a different prefix from `riscv32-unknown-elf-` — Ubuntu
ships `riscv64-unknown-elf-`, Homebrew `riscv64-elf-` — point OpenASIP at it:

```bash
export OA_RISCV_TOOL_PREFIX=riscv64-unknown-elf-
```

**Verified on macOS/arm64**: the RISC-V tutorial in the manual runs on the
generated processor in RTL simulation and produces the correct CRC, and the
in-tree `stdlibTest` reproduces its golden trace byte-for-byte. Both were
independently reproduced under GHDL on Linux, with identical cycle counts.

---

## 7. Known limitations on macOS

| limitation | status |
|---|---|
| **GUI tools** (ProDe, OSEd, Proxim, HDBEditor) | not built — see §1 |
| **VHDL simulation and synthesis** | **no simulator is installable from Homebrew.** There is no `ghdl` formula, only a cask, deprecated *"because it does not pass the macOS Gatekeeper check"* — and installing it leaves a broken symlink, because macOS deletes the unsigned `ghdl` binary moments after extraction. `brew install nvc` is a working alternative (it analyses and runs OpenASIP's generated VHDL at `--std=2008`); the OSS CAD Suite `darwin-arm64` bundle, which ships `ghdl` with `ghdl-yosys-plugin`, is the other candidate. |

---

## 8. Troubleshooting

Symptoms you may hit, and what they mean. Most correspond to portability bugs
that have been fixed; if you see one, your tree is probably older than the fix.

| symptom | cause |
|---|---|
| `configure: error: C++ compiler cannot create executables`, and `config.log` shows `clang++: error: invalid arch name '-arch aarch64'` | autoconf canonicalises Apple Silicon as `aarch64`, but clang spells it `arm64`. |
| `*** missing separator. Stop.` while `config.status` bootstraps depfiles | `echo -n` is not POSIX; the `/bin/sh` on macOS prints the flags literally and injects a newline into `VERSION_STRING`, corrupting every Makefile. **This looks exactly like "your make is too old", but it is not** — Apple's GNU Make 3.81 is fine. |
| `boost library not found` although boost is installed | you passed `CPPFLAGS` instead of `--with-boost`. See §4. |
| `fatal error: 'boost/filesystem/convenience.hpp' file not found` | that header was removed in Boost 1.87. |
| `ld: unknown options: --disable-new-dtags` | a GNU-ld-only flag; Apple's `ld` has no equivalent and needs none. |
| `dyld: Library not loaded: @rpath/libLLVMTCE.dylib` | the binary has no `LC_RPATH`. Note that `DYLD_LIBRARY_PATH` **cannot** rescue this: System Integrity Protection strips all `DYLD_*` variables when exec'ing a protected binary such as `/bin/sh`, which every make recipe goes through. The rpath must be recorded at link time. |
| `RuntimeLibcalls.inc: error: expected identifier` near `FREAD`/`FWRITE` | macOS `<sys/fcntl.h>` defines those as macros; LLVM declares enumerators with the same names. |
| `ar: *.o: No such file or directory` when assembling newlib's `libc.a`, or `ar: /3036: Read-only file system` | the archives hold **LLVM bitcode**, and Apple's cctools `ar` is Mach-O only. It does not fail loudly — it misreads the GNU long-filename table as member names. Use `llvm-ar`. |
| `fatal error: 'xercesc/util/XMLString.hpp' file not found` at *first compile*, after a successful install | the run-time backend-plugin compile was missing the third-party include paths — invisible where xerces lives in `/usr/include`. |
| `oacc` never finishes, printing `Compiling N files using N parallel jobs...` more than once, then `RuntimeError: An attempt has been made to start a new process before the current process has finished its bootstrapping phase` | `oacc` used `multiprocessing.Pool` without an `if __name__ == "__main__":` guard. Linux defaults to the **fork** start method so workers never re-import the script; macOS defaults to **spawn**, so every worker re-ran `oacc` and created another pool — a recursive process explosion. Fixed by using a thread pool (the work is I/O-bound). Symptom was a ~20-minute hang; correct time is ~20 seconds. |

---

## 9. Reporting problems

Please include:

- `sw_vers` and `uname -m`
- `clang --version` (both Apple's and `~/projects/local/bin/clang`)
- `brew list --versions boost xerces-c autoconf automake libtool cmake`
- the exact `./configure` line you used, and `config.log` if configure failed
