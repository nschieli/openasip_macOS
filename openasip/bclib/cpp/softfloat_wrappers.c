/*
    Copyright (C) 2026 Nicolas Schieli.

    This library is free software; you can redistribute it and/or
    modify it under the terms of the GNU Lesser General Public
    License as published by the Free Software Foundation; either
    version 2.1 of the License, or (at your option) any later version.

    This library is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
    Lesser General Public License for more details.

    You should have received a copy of the GNU Lesser General Public
    License along with this library; if not, write to the Free Software
    Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA
    02110-1301 USA

    SPDX-License-Identifier: LGPL-2.1-or-later
 */
/**
 * @file softfloat_wrappers.c
 *
 * Compiler-rt soft-float wrappers for 64-bit TTA.
 *
 * Forwards the compiler-rt libcall names the backend emits
 * (__extendsfdf2, __truncdfsf2, and the int<->float conversions) onto the
 * SoftFloat entry points provided by the target C library.
 *
 * The SoftFloat implementations these call into are the Berkeley SoftFloat
 * package by John R. Hauser, bundled with OpenASIP in newlib under
 * newlib/libc/sys/tce. Nothing from it is reproduced here; this file only
 * declares its entry points and bridges the two naming conventions.
 *
 * @author Nicolas Schieli 2026 (nschieli-no.spam-gmail.com)
 * @note rating: red
 */
#ifndef __TCE64__
/* 32-bit TTA: no wrappers needed, LowerMissingInstructions handles everything */
#else

/* SoftFloat types. These MUST match newlib's softfloat.h for the target
 * exactly, because they determine the CALLING CONVENTION of every extern
 * below -- not merely the size of a value.
 *
 * ⛔ float64 IS A STRUCT, NOT A SCALAR, AND GETTING THIS WRONG DOES NOT FAIL
 *    TO LINK. It was declared `unsigned long long` here, which links fine and
 *    is wrong at every call site: newlib returns the struct through a hidden
 *    pointer argument, so the caller's first real argument lands where the
 *    callee expects that pointer. Passing 1.0f produced
 *
 *      runtime error: Memory access at 1065353216 of size 4 is out of the
 *      address space
 *
 *    and 1065353216 is 0x3F800000, which IS 1.0f -- the float bit pattern
 *    being written to as an address. The address in the error message named
 *    the bug.
 *
 * ⚠ Both targets agree, so this is not a 64-bit peculiarity:
 *      newlib-1.17.0/tcele64-llvm/.../targ-include/softfloat.h
 *      newlib-1.17.0/tcele-llvm/.../targ-include/softfloat.h
 *    both declare `typedef struct { uint32 low, high; } float64;`
 *
 * ⇒ Not #include'd because these wrappers are compiled for the TARGET with no
 *   guarantee that header is on the include path. Replicated instead, with the
 *   size check below so a divergence is a compile error rather than a wild
 *   store at run time.
 */
typedef unsigned int float32;
typedef struct { unsigned int low, high; } float64;

/* Fails to compile if float64 stops being 8 bytes. Not _Static_assert, which
 * needs C11; this works in any C. */
typedef char softfloat_float64_must_be_8_bytes[(sizeof(float64) == 8) ? 1 : -1];
typedef char softfloat_float32_must_be_4_bytes[(sizeof(float32) == 4) ? 1 : -1];

/* Available SoftFloat functions in the emulation library */
extern float32 float64_to_float32(float64);
extern float64 float32_to_float64(float32);
extern int float32_to_int32_round_to_zero(float32);
extern int float64_to_int32_round_to_zero(float64);
extern unsigned int float32_to_uint32(float32);
extern float32 int32_to_float32(int);
extern float64 int32_to_float64(int);
extern float32 uint32_to_float32(unsigned int);

/* __truncdfsf2: double -> float */
float __truncdfsf2(double a) {
    union { double d; float64 u; } in;
    union { float32 u; float f; } out;
    in.d = a;
    out.u = float64_to_float32(in.u);
    return out.f;
}

/* __extendsfdf2: float -> double */
double __extendsfdf2(float a) {
    union { float f; float32 u; } in;
    union { float64 u; double d; } out;
    in.f = a;
    out.u = float32_to_float64(in.u);
    return out.d;
}

/* __fixsfsi: float -> int (truncate toward zero) */
int __fixsfsi(float a) {
    union { float f; float32 u; } in;
    in.f = a;
    return float32_to_int32_round_to_zero(in.u);
}

/* __fixdfsi: double -> int (truncate toward zero) */
int __fixdfsi(double a) {
    union { double d; float64 u; } in;
    in.d = a;
    return float64_to_int32_round_to_zero(in.u);
}

/* __fixunssfsi: float -> unsigned int (truncate toward zero) */
unsigned int __fixunssfsi(float a) {
    union { float f; float32 u; } in;
    in.f = a;
    return float32_to_uint32(in.u);
}

/* __fixunsdfsi: double -> unsigned int (truncate toward zero)
 * No direct float64_to_uint32, so convert via float32 */
unsigned int __fixunsdfsi(double a) {
    union { double d; float64 u; } in;
    in.d = a;
    float32 f32 = float64_to_float32(in.u);
    return float32_to_uint32(f32);
}

/* __floatsisf: int -> float */
float __floatsisf(int a) {
    union { float32 u; float f; } out;
    out.u = int32_to_float32(a);
    return out.f;
}

/* __floatsidf: int -> double */
double __floatsidf(int a) {
    union { float64 u; double d; } out;
    out.u = int32_to_float64(a);
    return out.d;
}

/* __floatunsisf: unsigned int -> float */
float __floatunsisf(unsigned int a) {
    union { float32 u; float f; } out;
    out.u = uint32_to_float32(a);
    return out.f;
}

/* __floatunsidf: unsigned int -> double
 * No direct uint32_to_float64, so convert via float32 then extend */
double __floatunsidf(unsigned int a) {
    union { float32 u; float f; } tmp;
    union { float64 u; double d; } out;
    tmp.u = uint32_to_float32(a);
    out.u = float32_to_float64(tmp.u);
    return out.d;
}

#endif /* __TCE64__ */
