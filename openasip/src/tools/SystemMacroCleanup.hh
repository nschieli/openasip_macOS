/*
    Copyright (c) 2026 Tampere University.
    Copyright (c) 2026 Nicolas Schieli.

    This file is part of TTA-Based Codesign Environment (TCE).

    Permission is hereby granted, free of charge, to any person obtaining a
    copy of this software and associated documentation files (the "Software"),
    to deal in the Software without restriction, including without limitation
    the rights to use, copy, modify, merge, publish, distribute, sublicense,
    and/or sell copies of the Software, and to permit persons to whom the
    Software is furnished to do so, subject to the following conditions:

    The above copyright notice and this permission notice shall be included in
    all copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
    THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
    FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
    DEALINGS IN THE SOFTWARE.
 */
/**
 * @file SystemMacroCleanup.hh
 *
 * Undefines platform macros that collide with identifiers declared in
 * third-party headers.
 *
 * Include this immediately BEFORE an <llvm/...> header in any translation
 * unit that may already have pulled in platform headers.
 *
 * WHY THIS EXISTS
 * ---------------
 * macOS's <sys/fcntl.h> defines FREAD and FWRITE as object-like macros -- they
 * are legacy BSD kernel file-access flags:
 *
 *     #define FREAD   0x00000001
 *     #define FWRITE  0x00000002
 *
 * LLVM's generated llvm/IR/RuntimeLibcalls.inc declares ENUMERATORS with those
 * exact names ("FREAD = 600,"). If any platform header pulled fcntl.h in
 * first, the enumerators are macro-expanded into integer literals and the LLVM
 * header fails to parse:
 *
 *     RuntimeLibcalls.inc:616:3: error: expected identifier
 *
 * glibc does not define FREAD/FWRITE, which is why this clash is invisible on
 * Linux and appears only on macOS/BSD.
 *
 * These macros are kernel-internal legacy flags that no portable user-space
 * code should depend on, so undefining them is safe. #undef of a macro that is
 * not defined is well-defined and a no-op, so no platform guard is needed and
 * this file costs nothing on Linux.
 *
 * NOTE: this header deliberately has NO include guard. The macros can be
 * reintroduced by any later platform header, so each inclusion must actually
 * re-run the #undefs. Guarding it would silently break the second use in a
 * translation unit.
 */

#undef FREAD
#undef FWRITE
