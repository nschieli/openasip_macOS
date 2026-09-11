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

entity ecp5_mul64_pipelined is
  port (
    clk          : in  std_logic;
    rstx         : in  std_logic;
    glock_in     : in  std_logic;
    glockreq_out : out std_logic;

    -- Trigger port (sets opcode)
    operation_in : in  std_logic_vector(0 downto 0);
    data_in1t_in : in  std_logic_vector(63 downto 0);
    load_in1t_in : in  std_logic;

    -- Second operand (multiplier)
    data_in2_in  : in  std_logic_vector(63 downto 0);
    load_in2_in  : in  std_logic;

    -- Result
    data_out1_out : out std_logic_vector(63 downto 0);

    -- Third operand (accumulator for mac64)
    data_in3_in  : in  std_logic_vector(63 downto 0);
    load_in3_in  : in  std_logic
  );
end entity ecp5_mul64_pipelined;

architecture rtl of ecp5_mul64_pipelined is

  -- Opcodes (must match ADF operation order)
  constant OP_MAC64 : std_logic_vector(0 downto 0) := "0";
  constant OP_MUL64 : std_logic_vector(0 downto 0) := "1";

  -- Shadow registers for non-trigger inputs
  signal shadow_in2_r : std_logic_vector(63 downto 0);
  signal shadow_in3_r : std_logic_vector(63 downto 0);
  signal data_in2     : std_logic_vector(63 downto 0);
  signal data_in3     : std_logic_vector(63 downto 0);

  -- Pipeline tracking
  signal op_s1_r      : std_logic_vector(0 downto 0);  -- operation in stage 1
  signal valid_s1_r   : std_logic;                      -- stage 1 has valid data

  -- Stage 1 inputs (captured operands)
  signal a_s1_r       : unsigned(63 downto 0);
  signal b_s1_r       : unsigned(63 downto 0);
  signal acc_s1_r     : unsigned(63 downto 0);  -- accumulator for mac64

  -- Partial products (combinatorial, each inferred as MULT18X18D)
  signal pp0          : unsigned(35 downto 0);  -- a_lo * b_lo
  signal pp1          : unsigned(35 downto 0);  -- a_lo * b_ml
  signal pp2          : unsigned(35 downto 0);  -- a_ml * b_lo
  signal pp3          : unsigned(35 downto 0);  -- a_lo * b_mh
  signal pp4          : unsigned(35 downto 0);  -- a_mh * b_lo
  signal pp5          : unsigned(35 downto 0);  -- a_ml * b_ml

  -- Registered partial products (end of stage 1)
  signal pp0_r        : unsigned(35 downto 0);
  signal pp1_r        : unsigned(35 downto 0);
  signal pp2_r        : unsigned(35 downto 0);
  signal pp3_r        : unsigned(35 downto 0);
  signal pp4_r        : unsigned(35 downto 0);
  signal pp5_r        : unsigned(35 downto 0);

  -- High partial product (simplified: only need bits 54-63 of result)
  signal pp_hi        : unsigned(9 downto 0);
  signal pp_hi_r      : unsigned(9 downto 0);

  -- Stage 2 pipeline tracking
  signal op_s2_r      : std_logic_vector(0 downto 0);
  signal valid_s2_r   : std_logic;
  signal acc_s2_r     : unsigned(63 downto 0);

  -- Stage 2 accumulation result
  signal mul_result   : unsigned(63 downto 0);

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

  -- Use direct input if loaded simultaneously with trigger, else shadow
  data_in2 <= data_in2_in when (load_in1t_in = '1' and load_in2_in = '1')
              else shadow_in2_r;
  data_in3 <= data_in3_in when (load_in1t_in = '1' and load_in3_in = '1')
              else shadow_in3_r;

  ---------------------------------------------------------------------------
  -- Stage 1: Capture operands + compute partial products
  ---------------------------------------------------------------------------

  -- Capture operands on trigger
  stage1_capture : process(clk, rstx)
  begin
    if rstx = '0' then
      a_s1_r     <= (others => '0');
      b_s1_r     <= (others => '0');
      acc_s1_r   <= (others => '0');
      op_s1_r    <= (others => '0');
      valid_s1_r <= '0';
    elsif rising_edge(clk) then
      if glock_in = '0' then
        valid_s1_r <= load_in1t_in;
        if load_in1t_in = '1' then
          op_s1_r <= operation_in;
          -- For mul64: a=in1t, b=in2
          -- For mac64: a=in1t (trigger), b=in2, acc=in3
          if operation_in = OP_MUL64 then
            a_s1_r   <= unsigned(data_in1t_in);
            b_s1_r   <= unsigned(data_in2);
            acc_s1_r <= (others => '0');
          else  -- OP_MAC64: result = in3 + in2 * in1t
            a_s1_r   <= unsigned(data_in1t_in);
            b_s1_r   <= unsigned(data_in2);
            acc_s1_r <= unsigned(data_in3);
          end if;
        end if;
      end if;
    end if;
  end process;

  -- Partial products (combinatorial, parallel DSP slices)
  -- Each 18x18 multiply infers one MULT18X18D on ECP5
  pp0 <= a_s1_r(17 downto  0) * b_s1_r(17 downto  0);  -- bits 0-35
  pp1 <= a_s1_r(17 downto  0) * b_s1_r(35 downto 18);  -- bits 18-53
  pp2 <= a_s1_r(35 downto 18) * b_s1_r(17 downto  0);  -- bits 18-53
  pp3 <= a_s1_r(17 downto  0) * b_s1_r(53 downto 36);  -- bits 36-71
  pp4 <= a_s1_r(53 downto 36) * b_s1_r(17 downto  0);  -- bits 36-71
  pp5 <= a_s1_r(35 downto 18) * b_s1_r(35 downto 18);  -- bits 36-71

  -- High bits (54-63): only 10 result bits needed, so use truncated products
  -- pp_hi captures all cross-terms that contribute to bits 54-63
  pp_hi <= resize(a_s1_r(17 downto 0) * b_s1_r(63 downto 54), 10)
         + resize(a_s1_r(63 downto 54) * b_s1_r(17 downto 0), 10)
         + resize(a_s1_r(35 downto 18) * b_s1_r(53 downto 36), 10)
         + resize(a_s1_r(53 downto 36) * b_s1_r(35 downto 18), 10);

  -- Register partial products (end of stage 1 / start of stage 2)
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
      end if;
    end if;
  end process;

  ---------------------------------------------------------------------------
  -- Stage 2: Shift-and-accumulate partial products (carry chain)
  ---------------------------------------------------------------------------

  -- Combine partial products into 64-bit result
  -- result = pp0 + (pp1 + pp2) << 18 + (pp3 + pp4 + pp5) << 36 + pp_hi << 54
  mul_result <= resize(pp0_r, 64)
              + shift_left(resize(pp1_r, 64) + resize(pp2_r, 64), 18)
              + shift_left(resize(pp3_r, 64) + resize(pp4_r, 64)
                         + resize(pp5_r, 64), 36)
              + shift_left(resize(pp_hi_r, 64), 54);

  -- Output register (end of stage 2)
  stage2_reg : process(clk, rstx)
  begin
    if rstx = '0' then
      result_r <= (others => '0');
    elsif rising_edge(clk) then
      if glock_in = '0' then
        if valid_s2_r = '1' then
          if op_s2_r = OP_MAC64 then
            result_r <= std_logic_vector(acc_s2_r + mul_result);
          else
            result_r <= std_logic_vector(mul_result);
          end if;
        end if;
      end if;
    end if;
  end process;

  data_out1_out <= result_r;

end architecture rtl;
