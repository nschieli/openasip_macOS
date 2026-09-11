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

entity ecp5_alu_pipelined is
  port (
    clk          : in  std_logic;
    rstx         : in  std_logic;
    glock_in     : in  std_logic;
    glockreq_out : out std_logic;

    -- Trigger port (sets opcode)
    operation_in : in  std_logic_vector(4 downto 0);  -- 5 bits for 23 ops
    data_in1t_in : in  std_logic_vector(63 downto 0);
    load_in1t_in : in  std_logic;

    -- Second operand
    data_in2_in  : in  std_logic_vector(63 downto 0);
    load_in2_in  : in  std_logic;

    -- Result
    data_out1_out : out std_logic_vector(63 downto 0)
  );
end entity ecp5_alu_pipelined;

architecture rtl of ecp5_alu_pipelined is

  -- Opcodes (must match ADF operation order — same as FUGen)
  constant OP_ABS64     : std_logic_vector(4 downto 0) := "00000";  -- 0
  constant OP_ADD64     : std_logic_vector(4 downto 0) := "00001";  -- 1
  constant OP_AND64     : std_logic_vector(4 downto 0) := "00010";  -- 2
  constant OP_EQ64      : std_logic_vector(4 downto 0) := "00011";  -- 3
  constant OP_GT64      : std_logic_vector(4 downto 0) := "00100";  -- 4
  constant OP_GTU64     : std_logic_vector(4 downto 0) := "00101";  -- 5
  constant OP_IOR64     : std_logic_vector(4 downto 0) := "00110";  -- 6
  constant OP_MAX64     : std_logic_vector(4 downto 0) := "00111";  -- 7
  constant OP_MAXU64    : std_logic_vector(4 downto 0) := "01000";  -- 8
  constant OP_MIN64     : std_logic_vector(4 downto 0) := "01001";  -- 9
  constant OP_MINU64    : std_logic_vector(4 downto 0) := "01010";  -- 10
  constant OP_NE64      : std_logic_vector(4 downto 0) := "01011";  -- 11
  constant OP_NEG64     : std_logic_vector(4 downto 0) := "01100";  -- 12
  constant OP_SHL1ADD64 : std_logic_vector(4 downto 0) := "01101";  -- 13
  constant OP_SHL2ADD64 : std_logic_vector(4 downto 0) := "01110";  -- 14
  constant OP_SHL64     : std_logic_vector(4 downto 0) := "01111";  -- 15
  constant OP_SHR64     : std_logic_vector(4 downto 0) := "10000";  -- 16
  constant OP_SHRU64    : std_logic_vector(4 downto 0) := "10001";  -- 17
  constant OP_SUB64     : std_logic_vector(4 downto 0) := "10010";  -- 18
  constant OP_SXH64     : std_logic_vector(4 downto 0) := "10011";  -- 19
  constant OP_SXQ64     : std_logic_vector(4 downto 0) := "10100";  -- 20
  constant OP_SXW64     : std_logic_vector(4 downto 0) := "10101";  -- 21
  constant OP_XOR64     : std_logic_vector(4 downto 0) := "10110";  -- 22

  -- Shadow register for non-trigger input
  signal shadow_in2_r : std_logic_vector(63 downto 0);
  signal data_in2     : std_logic_vector(63 downto 0);

  -- Stage 1 registers (pipeline: capture operands + opcode)
  signal op1_s1_r    : unsigned(63 downto 0);
  signal op2_s1_r    : unsigned(63 downto 0);
  signal opcode_s1_r : std_logic_vector(4 downto 0);
  signal valid_s1_r  : std_logic;

  -- Stage 2 result
  signal result       : std_logic_vector(63 downto 0);
  signal result_r     : std_logic_vector(63 downto 0);

begin

  glockreq_out <= '0';

  ---------------------------------------------------------------------------
  -- Shadow register for in2
  ---------------------------------------------------------------------------
  shadow_proc : process(clk, rstx)
  begin
    if rstx = '0' then
      shadow_in2_r <= (others => '0');
    elsif rising_edge(clk) then
      if glock_in = '0' and load_in2_in = '1' then
        shadow_in2_r <= data_in2_in;
      end if;
    end if;
  end process;

  data_in2 <= data_in2_in when (load_in1t_in = '1' and load_in2_in = '1')
              else shadow_in2_r;

  ---------------------------------------------------------------------------
  -- Stage 1: Register operands and opcode
  ---------------------------------------------------------------------------
  stage1 : process(clk, rstx)
  begin
    if rstx = '0' then
      op1_s1_r    <= (others => '0');
      op2_s1_r    <= (others => '0');
      opcode_s1_r <= (others => '0');
      valid_s1_r  <= '0';
    elsif rising_edge(clk) then
      if glock_in = '0' then
        valid_s1_r <= load_in1t_in;
        if load_in1t_in = '1' then
          op1_s1_r    <= unsigned(data_in1t_in);
          op2_s1_r    <= unsigned(data_in2);
          opcode_s1_r <= operation_in;
        end if;
      end if;
    end if;
  end process;

  ---------------------------------------------------------------------------
  -- Stage 2: Compute from registered inputs (combinatorial)
  ---------------------------------------------------------------------------
  compute : process(opcode_s1_r, op1_s1_r, op2_s1_r)
    variable a : unsigned(63 downto 0);
    variable b : unsigned(63 downto 0);
    variable r : unsigned(63 downto 0);
    variable sa : signed(63 downto 0);
    variable sb : signed(63 downto 0);
  begin
    a  := op1_s1_r;
    b  := op2_s1_r;
    sa := signed(a);
    sb := signed(b);
    r  := (others => '0');

    case opcode_s1_r is
      when OP_ABS64 =>
        if sa < 0 then r := unsigned(-sa); else r := a; end if;

      when OP_ADD64 =>
        r := a + b;

      when OP_AND64 =>
        r := a and b;

      when OP_EQ64 =>
        if a = b then r(0) := '1'; end if;

      when OP_GT64 =>
        if sa > sb then r(0) := '1'; end if;

      when OP_GTU64 =>
        if a > b then r(0) := '1'; end if;

      when OP_IOR64 =>
        r := a or b;

      when OP_MAX64 =>
        if sa >= sb then r := a; else r := b; end if;

      when OP_MAXU64 =>
        if a >= b then r := a; else r := b; end if;

      when OP_MIN64 =>
        if sa <= sb then r := a; else r := b; end if;

      when OP_MINU64 =>
        if a <= b then r := a; else r := b; end if;

      when OP_NE64 =>
        if a /= b then r(0) := '1'; end if;

      when OP_NEG64 =>
        r := unsigned(-sa);

      when OP_SHL1ADD64 =>
        r := (a(62 downto 0) & '0') + b;

      when OP_SHL2ADD64 =>
        r := (a(61 downto 0) & "00") + b;

      when OP_SHL64 =>
        r := shift_left(a, to_integer(b(5 downto 0)));

      when OP_SHR64 =>
        r := unsigned(shift_right(sa, to_integer(b(5 downto 0))));

      when OP_SHRU64 =>
        r := shift_right(a, to_integer(b(5 downto 0)));

      when OP_SUB64 =>
        r := a - b;

      when OP_SXH64 =>
        r := unsigned(resize(sa(15 downto 0), 64));

      when OP_SXQ64 =>
        r := unsigned(resize(sa(7 downto 0), 64));

      when OP_SXW64 =>
        r := unsigned(resize(sa(31 downto 0), 64));

      when OP_XOR64 =>
        r := a xor b;

      when others =>
        r := (others => '0');
    end case;

    result <= std_logic_vector(r);
  end process;

  ---------------------------------------------------------------------------
  -- Output register (end of stage 2)
  ---------------------------------------------------------------------------
  output_reg : process(clk, rstx)
  begin
    if rstx = '0' then
      result_r <= (others => '0');
    elsif rising_edge(clk) then
      if glock_in = '0' then
        if valid_s1_r = '1' then
          result_r <= result;
        end if;
      end if;
    end if;
  end process;

  data_out1_out <= result_r;

end architecture rtl;
