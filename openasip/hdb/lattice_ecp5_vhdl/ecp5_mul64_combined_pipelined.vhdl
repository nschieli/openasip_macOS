-- Copyright (c) 2026 Nicolas Schieli
--
-- DUAL LICENSED. Choose one:
--
--   1. CERN Open Hardware Licence Version 2 - Strongly Reciprocal
--      (CERN-OHL-S-2.0). You may use, modify and distribute this source and
--      Make Products from it under that licence. Note §3.2: including this
--      Source in a larger work makes that larger work Covered Source, and
--      §3.3(d) requires it be licensed as a whole under CERN-OHL-S. Conveying
--      a Product made from it obliges you to provide the Complete Source.
--      Full text: https://ohwr.org/cern_ohl_s_v2.txt
--
--   2. A commercial licence, which carries no reciprocal obligation and
--      permits use in closed-source designs. Contact the copyright holder.
--
-- This Source is distributed WITHOUT WARRANTY OF ANY KIND, express or implied,
-- to the extent permitted by applicable law. See the licence for details.
--
-- SPDX-License-Identifier: CERN-OHL-S-2.0
-- Source: verdon 7439f0b
--
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity ecp5_mul64_combined_pipelined is
  port (
    clk          : in  std_logic;
    rstx         : in  std_logic;
    glock_in     : in  std_logic;
    glockreq_out : out std_logic;

    -- Trigger port (sets opcode, 3 bits for 6 operations)
    operation_in : in  std_logic_vector(2 downto 0);
    data_in1t_in : in  std_logic_vector(63 downto 0);
    load_in1t_in : in  std_logic;

    -- Second operand
    data_in2_in  : in  std_logic_vector(63 downto 0);
    load_in2_in  : in  std_logic;

    -- Result
    data_out1_out : out std_logic_vector(63 downto 0);

    -- Third operand (accumulator for mac64/mac8x8)
    data_in3_in  : in  std_logic_vector(63 downto 0);
    load_in3_in  : in  std_logic
  );
end entity ecp5_mul64_combined_pipelined;

architecture rtl of ecp5_mul64_combined_pipelined is

  -- Opcodes (alphabetical: emac2x32, emac4x32, mac64, mac8x8, mul64, requant)
  constant OP_EMAC2X32 : std_logic_vector(2 downto 0) := "000";
  constant OP_EMAC4X32 : std_logic_vector(2 downto 0) := "001";
  constant OP_MAC64    : std_logic_vector(2 downto 0) := "010";
  constant OP_MAC8X8   : std_logic_vector(2 downto 0) := "011";
  constant OP_MUL64    : std_logic_vector(2 downto 0) := "100";
  constant OP_REQUANT  : std_logic_vector(2 downto 0) := "101";

  -- Shadow registers for non-trigger inputs
  signal shadow_in2_r : std_logic_vector(63 downto 0);
  signal shadow_in3_r : std_logic_vector(63 downto 0);
  signal data_in2     : std_logic_vector(63 downto 0);
  signal data_in3     : std_logic_vector(63 downto 0);

  ---------------------------------------------------------------------------
  -- 64-bit multiply pipeline signals (shared by mul64 and mac64)
  ---------------------------------------------------------------------------
  signal op_s1_r      : std_logic_vector(2 downto 0);
  signal valid_s1_r   : std_logic;

  signal a_s1_r       : unsigned(63 downto 0);
  signal b_s1_r       : unsigned(63 downto 0);
  signal acc_s1_r     : unsigned(63 downto 0);

  -- Partial products (each inferred as MULT18X18D on ECP5)
  signal pp0          : unsigned(35 downto 0);
  signal pp1          : unsigned(35 downto 0);
  signal pp2          : unsigned(35 downto 0);
  signal pp3          : unsigned(35 downto 0);
  signal pp4          : unsigned(35 downto 0);
  signal pp5          : unsigned(35 downto 0);

  signal pp0_r        : unsigned(35 downto 0);
  signal pp1_r        : unsigned(35 downto 0);
  signal pp2_r        : unsigned(35 downto 0);
  signal pp3_r        : unsigned(35 downto 0);
  signal pp4_r        : unsigned(35 downto 0);
  signal pp5_r        : unsigned(35 downto 0);

  signal pp_hi        : unsigned(9 downto 0);
  signal pp_hi_r      : unsigned(9 downto 0);

  signal op_s2_r      : std_logic_vector(2 downto 0);
  signal valid_s2_r   : std_logic;
  signal acc_s2_r     : unsigned(63 downto 0);

  signal mul_result   : unsigned(63 downto 0);

  ---------------------------------------------------------------------------
  -- SIMD int8 MAC signals (2-stage pipeline, same latency as mul64/mac64)
  -- Stage 1: 8 signed 8x8 multiplies (registered)
  -- Stage 2: tree-add + accumulate (registered)
  ---------------------------------------------------------------------------
  type int8_product_t is array (0 to 7) of signed(15 downto 0);
  signal simd_products   : int8_product_t;    -- combinatorial (stage 1)
  signal simd_products_r : int8_product_t;    -- registered (end of stage 1)
  signal simd_sum        : signed(18 downto 0);  -- combinatorial (stage 2)

  ---------------------------------------------------------------------------
  -- REQUANT pipeline signals (2-stage, same latency as mul64/mac64)
  -- Stage 1: Unpack inputs, add bias, register for multiply
  -- Stage 2: 32x32->64 multiply, round, shift, offset, clamp
  ---------------------------------------------------------------------------
  signal rq_acc_biased_r  : signed(31 downto 0);   -- registered at stage 1
  signal rq_multiplier_r  : signed(31 downto 0);   -- registered at stage 1
  signal rq_shift_r       : integer range -128 to 127;  -- registered at stage 1
  signal rq_offset_r      : signed(7 downto 0);    -- registered at stage 1
  signal rq_min_r         : signed(7 downto 0);    -- registered at stage 1
  signal rq_max_r         : signed(7 downto 0);    -- registered at stage 1

  -- REQUANT Stage 2 combinatorial signals
  signal rq_product   : signed(63 downto 0);
  signal rq_total_sh  : integer range 1 to 62;
  signal rq_round_val : signed(63 downto 0);
  signal rq_shifted   : signed(63 downto 0);
  signal rq_with_off  : signed(31 downto 0);
  signal rq_clamped   : signed(7 downto 0);

  ---------------------------------------------------------------------------
  -- EMAC2X32 pipeline signals (2-stage element-wise MAC)
  ---------------------------------------------------------------------------
  signal em_filter0_r    : signed(7 downto 0);    -- registered stage 1
  signal em_filter1_r    : signed(7 downto 0);    -- registered stage 1
  signal em_input0_off_r : signed(31 downto 0);   -- input_0 + offset, registered stage 1
  signal em_input1_off_r : signed(31 downto 0);   -- input_1 + offset, registered stage 1
  signal em_acc_lo_r     : signed(31 downto 0);   -- accumulator low, registered stage 1
  signal em_acc_hi_r     : signed(31 downto 0);   -- accumulator high, registered stage 1

  ---------------------------------------------------------------------------
  -- EMAC4X32 pipeline signals (2-stage dual-position int4 MAC)
  -- 4 MACs per cycle: 2 filter positions x 2 output channels
  ---------------------------------------------------------------------------
  signal e4_fa0_r        : signed(3 downto 0);    -- filter_a, channel 0 (int4)
  signal e4_fa1_r        : signed(3 downto 0);    -- filter_a, channel 1 (int4)
  signal e4_fb0_r        : signed(3 downto 0);    -- filter_b, channel 0 (int4)
  signal e4_fb1_r        : signed(3 downto 0);    -- filter_b, channel 1 (int4)
  signal e4_input_a_off_r : signed(31 downto 0);  -- input_a + offset, registered stage 1
  signal e4_input_b_off_r : signed(31 downto 0);  -- input_b + offset, registered stage 1
  signal e4_acc_lo_r     : signed(31 downto 0);   -- accumulator ch0, registered stage 1
  signal e4_acc_hi_r     : signed(31 downto 0);   -- accumulator ch1, registered stage 1

  -- Output register
  signal result_r     : std_logic_vector(63 downto 0);

begin

  glockreq_out <= '0';

  ---------------------------------------------------------------------------
  -- Shadow registers: capture non-trigger inputs when loaded
  ---------------------------------------------------------------------------
  shadow_regs : process(clk, rstx)
  begin
    if rstx = '0' then
      shadow_in2_r <= (others => '0');
      shadow_in3_r <= (others => '0');
    elsif rising_edge(clk) then
      if glock_in = '0' then
        if load_in2_in = '1' then
          shadow_in2_r <= data_in2_in;
        end if;
        if load_in3_in = '1' then
          shadow_in3_r <= data_in3_in;
        end if;
      end if;
    end if;
  end process;

  data_in2 <= data_in2_in when (load_in1t_in = '1' and load_in2_in = '1')
              else shadow_in2_r;
  data_in3 <= data_in3_in when (load_in1t_in = '1' and load_in3_in = '1')
              else shadow_in3_r;

  ---------------------------------------------------------------------------
  -- SIMD int8 MAC: Stage 1 — 8 signed 8x8 multiplies (combinatorial)
  -- Products are registered alongside the 64-bit partial products.
  ---------------------------------------------------------------------------

  -- SIMD products computed from stage 1 registered operands (a_s1_r, b_s1_r)
  simd_gen : for i in 0 to 7 generate
    simd_products(i) <= signed(std_logic_vector(a_s1_r(i*8+7 downto i*8)))
                      * signed(std_logic_vector(b_s1_r(i*8+7 downto i*8)));
  end generate;

  -- SIMD Stage 2: tree-add of registered products (combinatorial)
  simd_sum <= resize(simd_products_r(0), 19) + resize(simd_products_r(1), 19)
            + resize(simd_products_r(2), 19) + resize(simd_products_r(3), 19)
            + resize(simd_products_r(4), 19) + resize(simd_products_r(5), 19)
            + resize(simd_products_r(6), 19) + resize(simd_products_r(7), 19);

  ---------------------------------------------------------------------------
  -- 64-bit multiply pipeline: Stage 1 (capture + partial products)
  ---------------------------------------------------------------------------

  stage1_capture : process(clk, rstx)
  begin
    if rstx = '0' then
      a_s1_r     <= (others => '0');
      b_s1_r     <= (others => '0');
      acc_s1_r   <= (others => '0');
      op_s1_r    <= (others => '0');
      valid_s1_r <= '0';
      rq_acc_biased_r  <= (others => '0');
      rq_multiplier_r  <= (others => '0');
      rq_shift_r       <= 0;
      rq_offset_r      <= (others => '0');
      rq_min_r         <= (others => '0');
      rq_max_r         <= (others => '0');
      em_filter0_r     <= (others => '0');
      em_filter1_r     <= (others => '0');
      em_input0_off_r  <= (others => '0');
      em_input1_off_r  <= (others => '0');
      em_acc_lo_r      <= (others => '0');
      em_acc_hi_r      <= (others => '0');
      e4_fa0_r         <= (others => '0');
      e4_fa1_r         <= (others => '0');
      e4_fb0_r         <= (others => '0');
      e4_fb1_r         <= (others => '0');
      e4_input_a_off_r <= (others => '0');
      e4_input_b_off_r <= (others => '0');
      e4_acc_lo_r      <= (others => '0');
      e4_acc_hi_r      <= (others => '0');
    elsif rising_edge(clk) then
      if glock_in = '0' then
        -- All operations enter the 2-stage pipeline
        if load_in1t_in = '1' then
          valid_s1_r <= '1';
          op_s1_r    <= operation_in;
          a_s1_r     <= unsigned(data_in1t_in);
          b_s1_r     <= unsigned(data_in2);
          if operation_in = OP_MUL64 then
            acc_s1_r <= (others => '0');
          elsif operation_in = OP_REQUANT then
            acc_s1_r <= (others => '0');  -- not used for requant
            -- Unpack and register for stage 2
            rq_acc_biased_r <= signed(data_in1t_in(31 downto 0))
                             + signed(data_in2(31 downto 0));        -- acc + bias
            rq_multiplier_r <= signed(data_in2(63 downto 32));       -- multiplier
            rq_shift_r      <= to_integer(signed(data_in3(31 downto 24)));
            rq_offset_r     <= signed(data_in3(23 downto 16));
            rq_min_r        <= signed(data_in3(15 downto 8));
            rq_max_r        <= signed(data_in3(7 downto 0));
          elsif operation_in = OP_EMAC2X32 then
            acc_s1_r <= (others => '0');  -- not used for emac2x32
            -- Unpack filter bytes from data_in2[15:0]
            em_filter0_r <= signed(data_in2(7 downto 0));    -- filter_0
            em_filter1_r <= signed(data_in2(15 downto 8));   -- filter_1
            -- Unpack input bytes from data_in3[15:0], add offset from data_in2[63:32]
            em_input0_off_r <= resize(signed(data_in3(7 downto 0)), 32)
                             + signed(data_in2(63 downto 32));
            em_input1_off_r <= resize(signed(data_in3(15 downto 8)), 32)
                             + signed(data_in2(63 downto 32));
            -- Unpack accumulators from data_in1t_in
            em_acc_lo_r <= signed(data_in1t_in(31 downto 0));
            em_acc_hi_r <= signed(data_in1t_in(63 downto 32));
          elsif operation_in = OP_EMAC4X32 then
            acc_s1_r <= (others => '0');  -- not used for emac4x32
            -- Unpack 4 int4 filters from data_in2[15:0]:
            --   fa[7:0] = {f_a1[7:4], f_a0[3:0]} at position a
            --   fb[7:0] = {f_b1[7:4], f_b0[3:0]} at position b
            e4_fa0_r <= signed(data_in2(3 downto 0));     -- filter_a, ch0
            e4_fa1_r <= signed(data_in2(7 downto 4));     -- filter_a, ch1
            e4_fb0_r <= signed(data_in2(11 downto 8));    -- filter_b, ch0
            e4_fb1_r <= signed(data_in2(15 downto 12));   -- filter_b, ch1
            -- Unpack 2 int8 inputs from data_in2[31:16], add offset from data_in2[63:32]
            e4_input_a_off_r <= resize(signed(data_in2(23 downto 16)), 32)
                              + signed(data_in2(63 downto 32));
            e4_input_b_off_r <= resize(signed(data_in2(31 downto 24)), 32)
                              + signed(data_in2(63 downto 32));
            -- Unpack accumulators from data_in1t_in
            e4_acc_lo_r <= signed(data_in1t_in(31 downto 0));
            e4_acc_hi_r <= signed(data_in1t_in(63 downto 32));
          else  -- OP_MAC64 or OP_MAC8X8
            acc_s1_r <= unsigned(data_in3);
          end if;
        else
          valid_s1_r <= '0';
        end if;
      end if;
    end if;
  end process;

  -- Partial products (combinatorial, parallel DSP slices)
  pp0 <= a_s1_r(17 downto  0) * b_s1_r(17 downto  0);
  pp1 <= a_s1_r(17 downto  0) * b_s1_r(35 downto 18);
  pp2 <= a_s1_r(35 downto 18) * b_s1_r(17 downto  0);
  pp3 <= a_s1_r(17 downto  0) * b_s1_r(53 downto 36);
  pp4 <= a_s1_r(53 downto 36) * b_s1_r(17 downto  0);
  pp5 <= a_s1_r(35 downto 18) * b_s1_r(35 downto 18);

  pp_hi <= resize(a_s1_r(17 downto 0) * b_s1_r(63 downto 54), 10)
         + resize(a_s1_r(63 downto 54) * b_s1_r(17 downto 0), 10)
         + resize(a_s1_r(35 downto 18) * b_s1_r(53 downto 36), 10)
         + resize(a_s1_r(53 downto 36) * b_s1_r(35 downto 18), 10);

  stage1_reg : process(clk, rstx)
  begin
    if rstx = '0' then
      pp0_r      <= (others => '0');
      pp1_r      <= (others => '0');
      pp2_r      <= (others => '0');
      pp3_r      <= (others => '0');
      pp4_r      <= (others => '0');
      pp5_r      <= (others => '0');
      pp_hi_r    <= (others => '0');
      op_s2_r    <= (others => '0');
      valid_s2_r <= '0';
      acc_s2_r   <= (others => '0');
      -- SIMD: register int8 products (stage 1 -> stage 2)
      for i in 0 to 7 loop
        simd_products_r(i) <= (others => '0');
      end loop;
    elsif rising_edge(clk) then
      if glock_in = '0' then
        pp0_r      <= pp0;
        pp1_r      <= pp1;
        pp2_r      <= pp2;
        pp3_r      <= pp3;
        pp4_r      <= pp4;
        pp5_r      <= pp5;
        pp_hi_r    <= pp_hi;
        op_s2_r    <= op_s1_r;
        valid_s2_r <= valid_s1_r;
        acc_s2_r   <= acc_s1_r;
        -- SIMD: register int8 products (stage 1 -> stage 2)
        simd_products_r <= simd_products;
      end if;
    end if;
  end process;

  ---------------------------------------------------------------------------
  -- 64-bit multiply pipeline: Stage 2 (shift-and-accumulate)
  ---------------------------------------------------------------------------

  mul_result <= resize(pp0_r, 64)
              + shift_left(resize(pp1_r, 64) + resize(pp2_r, 64), 18)
              + shift_left(resize(pp3_r, 64) + resize(pp4_r, 64)
                         + resize(pp5_r, 64), 36)
              + shift_left(resize(pp_hi_r, 64), 54);

  ---------------------------------------------------------------------------
  -- REQUANT Stage 2: combinatorial computation from registered stage 1 values
  ---------------------------------------------------------------------------
  rq_comb : process(rq_acc_biased_r, rq_multiplier_r, rq_shift_r,
                    rq_offset_r, rq_min_r, rq_max_r)
    variable v_product  : signed(63 downto 0);
    variable v_tshift   : integer;
    variable v_round    : signed(63 downto 0);
    variable v_shifted  : signed(63 downto 0);
    variable v_with_off : signed(31 downto 0);
  begin
    -- 32x32 -> 64-bit signed multiply
    v_product := rq_acc_biased_r * rq_multiplier_r;
    -- total_shift = 31 - shift
    v_tshift := 31 - rq_shift_r;
    -- Rounding: add 1 << (total_shift - 1)
    v_round := (others => '0');
    if v_tshift >= 1 and v_tshift <= 62 then
      v_round(v_tshift - 1) := '1';
    end if;
    -- Arithmetic right shift with rounding
    v_shifted := shift_right(v_product + v_round, v_tshift);
    -- Add output offset
    v_with_off := v_shifted(31 downto 0) + resize(rq_offset_r, 32);
    -- Assign to signals for output_reg
    rq_product   <= v_product;
    if v_tshift >= 1 and v_tshift <= 62 then
      rq_total_sh <= v_tshift;
    else
      rq_total_sh <= 31;  -- safe default
    end if;
    rq_round_val <= v_round;
    rq_shifted   <= v_shifted;
    rq_with_off  <= v_with_off;
    -- Clamp to [min, max]
    if v_with_off < resize(rq_min_r, 32) then
      rq_clamped <= rq_min_r;
    elsif v_with_off > resize(rq_max_r, 32) then
      rq_clamped <= rq_max_r;
    else
      rq_clamped <= v_with_off(7 downto 0);
    end if;
  end process;

  ---------------------------------------------------------------------------
  -- Output register: all operations share 2-cycle pipeline latency
  ---------------------------------------------------------------------------
  output_reg : process(clk, rstx)
  begin
    if rstx = '0' then
      result_r <= (others => '0');
    elsif rising_edge(clk) then
      if glock_in = '0' then
        if valid_s2_r = '1' then
          if op_s2_r = OP_MAC8X8 then
            -- mac8x8: accumulator + sum of 8 int8 products
            result_r <= std_logic_vector(
              signed(acc_s2_r) + resize(simd_sum, 64));
          elsif op_s2_r = OP_REQUANT then
            -- requant: sign-extend int8 result to 64 bits
            result_r <= std_logic_vector(resize(rq_clamped, 64));
          elsif op_s2_r = OP_EMAC2X32 then
            -- emac2x32: 2-lane element-wise MAC (8x32->32 truncated, accumulate)
            result_r(63 downto 32) <= std_logic_vector(
              em_acc_hi_r + resize(em_filter1_r * em_input1_off_r, 32));
            result_r(31 downto 0) <= std_logic_vector(
              em_acc_lo_r + resize(em_filter0_r * em_input0_off_r, 32));
          elsif op_s2_r = OP_EMAC4X32 then
            -- emac4x32: dual-position 2-lane int4 MAC (4 MACs/cycle)
            result_r(31 downto 0) <= std_logic_vector(
              e4_acc_lo_r + resize(e4_fa0_r * e4_input_a_off_r, 32)
                          + resize(e4_fb0_r * e4_input_b_off_r, 32));
            result_r(63 downto 32) <= std_logic_vector(
              e4_acc_hi_r + resize(e4_fa1_r * e4_input_a_off_r, 32)
                          + resize(e4_fb1_r * e4_input_b_off_r, 32));
          elsif op_s2_r = OP_MAC64 then
            result_r <= std_logic_vector(acc_s2_r + mul_result);
          else  -- OP_MUL64
            result_r <= std_logic_vector(mul_result);
          end if;
        end if;
      end if;
    end if;
  end process;

  data_out1_out <= result_r;

end architecture rtl;
