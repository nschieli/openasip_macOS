/*
 * __trunctfdf2 for 32-bit RISC-V: binary128 (long double) -> binary64 (double).
 *
 * WHY THIS FILE EXISTS
 *
 * The RISC-V ABI makes `long double` a binary128 quad (LDBL_MANT_DIG == 113).
 * newlib's vfprintf therefore truncates a long double vararg to double —
 * it does so even with long-double IO disabled, see vfprintf.c's _NO_LONGDBL
 * branch — which emits a call to __trunctfdf2. So EVERY program that uses
 * printf needs this helper.
 *
 * libgcc supplies it (soft-fp, which works in 32-bit limbs). compiler-rt does
 * not: its quad support is gated on CRT_HAS_TF_MODE, which requires
 * CRT_HAS_128BIT, which requires a native __int128 — a type clang does not
 * offer on any 32-bit target. So on riscv32 compiler-rt's trunctfdf2.c
 * compiles to an empty object, and this is the one helper that keeps the
 * GNU-toolchain-free path from linking real programs.
 *
 * Written for OpenASIP rather than copied from compiler-rt: that code is
 * Apache-2.0-with-LLVM-exception, which does not combine with this project's
 * LGPL-2.1. The algorithm below is the standard IEEE-754 shift-and-round
 * conversion, implemented over clang's _BitInt(128) (supported on 32-bit
 * targets, unlike __int128).
 *
 * Rounding is round-to-nearest, ties-to-even. Signalling NaNs are quieted,
 * as the operation is defined to do; NaN payload bits are preserved as far as
 * the narrower destination allows.
 *
 * Copyright (C) 2026 Tampere University.
 *
 * This library is free software; you can redistribute it and/or modify it
 * under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation; either version 2.1 of the License, or (at
 * your option) any later version.
 */

typedef unsigned _BitInt(128) oa_u128;
typedef unsigned long long oa_u64;

/* binary128 */
#define SRC_SIG_BITS 112
#define SRC_EXP_MAX 0x7fffu
#define SRC_EXP_BIAS 16383

/* binary64 */
#define DST_SIG_BITS 52
#define DST_EXP_MAX 0x7ffu
#define DST_EXP_BIAS 1023

/* Bits dropped by the conversion, and the value of "exactly half of them". */
#define SIG_DROP (SRC_SIG_BITS - DST_SIG_BITS) /* 60 */

/*
 * The conversion, expressed on the raw bit patterns. Kept separate from the
 * ABI wrapper below so it can be exercised on a host where `long double` is
 * not binary128 — see test_trunctfdf2.c.
 */
double oa_trunctfdf2_bits(oa_u128 aRep, oa_u64 *resultBits) {
    const oa_u128 sigMask = (((oa_u128)1) << SRC_SIG_BITS) - 1;
    const oa_u128 roundMask = (((oa_u128)1) << SIG_DROP) - 1;
    const oa_u128 halfway = ((oa_u128)1) << (SIG_DROP - 1);

    const oa_u64 sign = (oa_u64)(aRep >> 127) << 63;
    const unsigned srcExp = (unsigned)((aRep >> SRC_SIG_BITS) & SRC_EXP_MAX);
    const oa_u128 srcSig = aRep & sigMask;

    oa_u64 absResult;

    if (srcExp == SRC_EXP_MAX) {
        /* Infinity, or NaN. */
        if (srcSig == 0) {
            absResult = (oa_u64)DST_EXP_MAX << DST_SIG_BITS;
        } else {
            /* Quiet the result and keep as much of the payload as fits. */
            absResult = (oa_u64)DST_EXP_MAX << DST_SIG_BITS;
            absResult |= (oa_u64)1 << (DST_SIG_BITS - 1);
            absResult |= (oa_u64)(srcSig >> SIG_DROP) &
                         (((oa_u64)1 << (DST_SIG_BITS - 1)) - 1);
        }
    } else {
        /*
         * Value is (-1)^s * 1.srcSig * 2^(srcExp - SRC_EXP_BIAS), or a source
         * subnormal when srcExp == 0 — those are around 1e-4932, far below
         * anything a double can represent, so they land on zero below.
         */
        const int dstExp = (int)srcExp - SRC_EXP_BIAS + DST_EXP_BIAS;

        if (srcExp != 0 && dstExp >= (int)DST_EXP_MAX) {
            /* Overflows the destination range: round to infinity. */
            absResult = (oa_u64)DST_EXP_MAX << DST_SIG_BITS;
        } else if (srcExp != 0 && dstExp > 0) {
            /*
             * Normal in both formats. Shifting the biased source
             * representation keeps the exponent field directly above the
             * significand, so a rounding carry propagates into the exponent
             * by itself — which is exactly the desired behaviour when the
             * significand rounds up to the next power of two.
             */
            const oa_u128 aAbs = aRep & ((((oa_u128)1) << 127) - 1);
            absResult = (oa_u64)(aAbs >> SIG_DROP);
            absResult -= (oa_u64)(SRC_EXP_BIAS - DST_EXP_BIAS) << DST_SIG_BITS;

            const oa_u128 roundBits = aAbs & roundMask;
            if (roundBits > halfway)
                absResult++;
            else if (roundBits == halfway)
                absResult += absResult & 1;
        } else {
            /*
             * Subnormal in the destination, or zero. Denormalize the
             * significand, keeping a sticky bit so that the rounding below
             * still sees whether anything was shifted out.
             */
            const oa_u128 significand =
                srcExp == 0 ? srcSig : (srcSig | (((oa_u128)1) << SRC_SIG_BITS));
            const int shift = 1 - dstExp;

            if (srcExp == 0 || shift > SRC_SIG_BITS + 1) {
                /* Everything is shifted out; the sign is still preserved. */
                absResult = 0;
            } else {
                const int sticky = (significand << (128 - shift)) != 0;
                const oa_u128 denormalized =
                    (significand >> shift) | (oa_u128)sticky;

                absResult = (oa_u64)(denormalized >> SIG_DROP);
                const oa_u128 roundBits = denormalized & roundMask;
                if (roundBits > halfway)
                    absResult++;
                else if (roundBits == halfway)
                    absResult += absResult & 1;
            }
        }
    }

    absResult |= sign;
    if (resultBits != 0)
        *resultBits = absResult;

    double result;
    __builtin_memcpy(&result, &absResult, sizeof result);
    return result;
}

#ifndef OA_TRUNCTFDF2_NO_ABI_WRAPPER
double __trunctfdf2(long double a) {
    oa_u128 aRep;
    __builtin_memcpy(&aRep, &a, sizeof aRep);
    return oa_trunctfdf2_bits(aRep, 0);
}
#endif
