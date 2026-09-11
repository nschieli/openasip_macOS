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

#include "OSAL.hh"

//////////////////////////////////////////////////////////////////////////////
// MAC8X8 - Packed int8 SIMD multiply-accumulate (8 lanes)
//
// Multiplies 8 pairs of signed 8-bit integers packed in 64-bit operands
// and accumulates into a 64-bit result.
//
// IO(1) = accumulator (signed 64-bit)
// IO(2) = packed int8 vector A (8 x int8 in 64 bits)
// IO(3) = packed int8 vector B (8 x int8 in 64 bits)
// IO(4) = result = acc + sum(a[i] * b[i]) for i in 0..7
//
// Byte order: element 0 is the least-significant byte.
//////////////////////////////////////////////////////////////////////////////
OPERATION(MAC8X8)

TRIGGER
    SLongWord acc = LONG(1);
    ULongWord a = ULONG(2);
    ULongWord b = ULONG(3);

    SLongWord sum = 0;
    for (int i = 0; i < 8; i++) {
        // Extract signed int8 from each byte position
        signed char ai = (signed char)((a >> (i * 8)) & 0xFF);
        signed char bi = (signed char)((b >> (i * 8)) & 0xFF);
        sum += (SLongWord)ai * (SLongWord)bi;
    }

    IO(4) = (SLongWord)(acc + sum);
END_TRIGGER;

END_OPERATION(MAC8X8)

//////////////////////////////////////////////////////////////////////////////
// EMAC2X32 - Element-wise 2-channel int8 multiply-accumulate
//
// IO(1) = {acc_hi[63:32], acc_lo[31:0]} two packed int32 accumulators
// IO(2) = {input_offset[63:32], unused[31:16], filter_1[15:8], filter_0[7:0]}
// IO(3) = {unused[63:16], input_1[15:8], input_0[7:0]}
// IO(4) = updated accumulators
//
// acc_lo += sext(filter_0) * (sext(input_0) + offset)
// acc_hi += sext(filter_1) * (sext(input_1) + offset)
//////////////////////////////////////////////////////////////////////////////
OPERATION(EMAC2X32)

TRIGGER
    SLongWord acc_packed = LONG(1);
    int32_t acc_lo = (int32_t)(acc_packed & 0xFFFFFFFFLL);
    int32_t acc_hi = (int32_t)((acc_packed >> 32) & 0xFFFFFFFFLL);

    ULongWord packed2 = ULONG(2);
    int8_t filter_0 = (int8_t)(packed2 & 0xFF);
    int8_t filter_1 = (int8_t)((packed2 >> 8) & 0xFF);
    int32_t offset  = (int32_t)((packed2 >> 32) & 0xFFFFFFFFULL);

    ULongWord packed3 = ULONG(3);
    int8_t input_0 = (int8_t)(packed3 & 0xFF);
    int8_t input_1 = (int8_t)((packed3 >> 8) & 0xFF);

    acc_lo += (int32_t)filter_0 * ((int32_t)input_0 + offset);
    acc_hi += (int32_t)filter_1 * ((int32_t)input_1 + offset);

    IO(4) = ((SLongWord)(uint32_t)acc_hi << 32) | (SLongWord)(uint32_t)acc_lo;
END_TRIGGER;

END_OPERATION(EMAC2X32)

//////////////////////////////////////////////////////////////////////////////
// EMAC4X32 - Dual-position 2-channel int4 multiply-accumulate (4 MACs/cycle)
//
// IO(1) = {acc_hi[63:32], acc_lo[31:0]} two packed int32 accumulators
// IO(2) = {offset[63:32], input_b[31:24], input_a[23:16], fb[15:8], fa[7:0]}
//   fa = {f_a1[7:4], f_a0[3:0]} packed int4 filters at position a
//   fb = {f_b1[7:4], f_b0[3:0]} packed int4 filters at position b
// IO(3) = unused
// IO(4) = updated accumulators
//
// acc_lo += sext4(fa0)*(sext8(input_a)+offset) + sext4(fb0)*(sext8(input_b)+offset)
// acc_hi += sext4(fa1)*(sext8(input_a)+offset) + sext4(fb1)*(sext8(input_b)+offset)
//////////////////////////////////////////////////////////////////////////////
OPERATION(EMAC4X32)

TRIGGER
    SLongWord acc_packed = LONG(1);
    int32_t acc_lo = (int32_t)(acc_packed & 0xFFFFFFFFLL);
    int32_t acc_hi = (int32_t)((acc_packed >> 32) & 0xFFFFFFFFLL);

    ULongWord packed2 = ULONG(2);
    // Unpack 4 int4 filters (sign-extend from 4-bit)
    int32_t fa0_raw = (int32_t)(packed2 & 0xF);
    int32_t fa0 = (fa0_raw & 0x8) ? (fa0_raw | ~0xF) : fa0_raw;
    int32_t fa1_raw = (int32_t)((packed2 >> 4) & 0xF);
    int32_t fa1 = (fa1_raw & 0x8) ? (fa1_raw | ~0xF) : fa1_raw;
    int32_t fb0_raw = (int32_t)((packed2 >> 8) & 0xF);
    int32_t fb0 = (fb0_raw & 0x8) ? (fb0_raw | ~0xF) : fb0_raw;
    int32_t fb1_raw = (int32_t)((packed2 >> 12) & 0xF);
    int32_t fb1 = (fb1_raw & 0x8) ? (fb1_raw | ~0xF) : fb1_raw;
    // Unpack 2 int8 inputs (sign-extend from 8-bit)
    int32_t input_a = (int32_t)(int8_t)((packed2 >> 16) & 0xFF);
    int32_t input_b = (int32_t)(int8_t)((packed2 >> 24) & 0xFF);
    int32_t offset  = (int32_t)((packed2 >> 32) & 0xFFFFFFFFULL);

    int32_t ia_off = input_a + offset;
    int32_t ib_off = input_b + offset;

    acc_lo += fa0 * ia_off + fb0 * ib_off;
    acc_hi += fa1 * ia_off + fb1 * ib_off;

    IO(4) = ((SLongWord)(uint32_t)acc_hi << 32) | (SLongWord)(uint32_t)acc_lo;
END_TRIGGER;

END_OPERATION(EMAC4X32)

//////////////////////////////////////////////////////////////////////////////
// REQUANT - Fused post-MAC int8 requantization pipeline
//
// IO(1) = accumulator (signed 64-bit, lower 32 bits = dot product result)
// IO(2) = {multiplier[63:32], bias[31:0]} packed as uint64
// IO(3) = {shift[31:24], offset[23:16], min[15:8], max[7:0]} in lower 32 bits
// IO(4) = result: int8 sign-extended to 64 bits
//
// Algorithm (single-rounding MultiplyByQuantizedMultiplier):
//   acc = int32(IO(1)) + bias
//   total_shift = 31 - shift
//   result = (int64(acc) * int64(multiplier) + (1 << (total_shift-1)))
//            >> total_shift
//   result += offset
//   result = clamp(result, min, max)
//   output = sign_extend(int8(result))
//////////////////////////////////////////////////////////////////////////////
OPERATION(REQUANT)

TRIGGER
    // Unpack inputs
    SLongWord acc_raw = LONG(1);
    int32_t acc = (int32_t)acc_raw;

    ULongWord packed2 = ULONG(2);
    int32_t bias       = (int32_t)(packed2 & 0xFFFFFFFFULL);
    int32_t multiplier = (int32_t)((packed2 >> 32) & 0xFFFFFFFFULL);

    ULongWord packed3 = ULONG(3);
    int8_t act_max       = (int8_t)(packed3 & 0xFF);
    int8_t act_min       = (int8_t)((packed3 >> 8) & 0xFF);
    int8_t output_offset = (int8_t)((packed3 >> 16) & 0xFF);
    int8_t shift         = (int8_t)((packed3 >> 24) & 0xFF);

    // Step 1: Add bias
    int32_t acc_biased = acc + bias;

    // Step 2-4: MultiplyByQuantizedMultiplier (single-rounding)
    int32_t total_shift = 31 - (int32_t)shift;
    int64_t round = (int64_t)1 << (total_shift - 1);
    int64_t product = (int64_t)acc_biased * (int64_t)multiplier;
    int64_t scaled = (product + round) >> total_shift;

    // Step 5: Add output zero-point
    int32_t result = (int32_t)scaled + (int32_t)output_offset;

    // Step 6-7: Clamp
    if (result < (int32_t)act_min) result = (int32_t)act_min;
    if (result > (int32_t)act_max) result = (int32_t)act_max;

    // Step 8: Output as sign-extended int8
    IO(4) = (SLongWord)(int8_t)result;
END_TRIGGER;

END_OPERATION(REQUANT)
