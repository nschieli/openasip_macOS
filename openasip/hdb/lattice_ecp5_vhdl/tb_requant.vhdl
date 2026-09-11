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

entity tb_requant is
end entity tb_requant;

architecture sim of tb_requant is

  constant CLK_PERIOD : time := 20 ns;

  signal clk      : std_logic := '0';
  signal rstx     : std_logic := '0';
  signal glock    : std_logic := '0';
  signal glockreq : std_logic;
  signal sim_done : boolean := false;

  signal operation : std_logic_vector(1 downto 0) := "00";
  signal data_t1   : std_logic_vector(63 downto 0) := (others => '0');
  signal load_t1   : std_logic := '0';
  signal data_o1   : std_logic_vector(63 downto 0) := (others => '0');
  signal load_o1   : std_logic := '0';
  signal data_r1   : std_logic_vector(63 downto 0);
  signal data_o2   : std_logic_vector(63 downto 0) := (others => '0');
  signal load_o2   : std_logic := '0';

  constant OP_REQUANT : std_logic_vector(1 downto 0) := "11";

  -- Pack {multiplier, bias} into in2
  function pack_mult_bias(mult, bias : integer) return std_logic_vector is
    variable r : std_logic_vector(63 downto 0);
  begin
    r(31 downto 0)  := std_logic_vector(to_signed(bias, 32));
    r(63 downto 32) := std_logic_vector(to_signed(mult, 32));
    return r;
  end function;

  -- Pack {shift, offset, min, max} into in3
  function pack_ctrl(sh, off, mn, mx : integer) return std_logic_vector is
    variable r : std_logic_vector(63 downto 0);
  begin
    r := (others => '0');
    r(7 downto 0)   := std_logic_vector(to_signed(mx, 8));
    r(15 downto 8)  := std_logic_vector(to_signed(mn, 8));
    r(23 downto 16) := std_logic_vector(to_signed(off, 8));
    r(31 downto 24) := std_logic_vector(to_signed(sh, 8));
    return r;
  end function;

  signal test_count : integer := 0;
  signal pass_count : integer := 0;

begin

  clk <= not clk after CLK_PERIOD / 2 when not sim_done else '0';

  dut : entity work.ecp5_mul64_simd_pipelined
    port map (
      clk          => clk,
      rstx         => rstx,
      glock_in     => glock,
      glockreq_out => glockreq,
      operation_in => operation,
      data_in1t_in => data_t1,
      load_in1t_in => load_t1,
      data_in2_in  => data_o1,
      load_in2_in  => load_o1,
      data_out1_out => data_r1,
      data_in3_in  => data_o2,
      load_in3_in  => load_o2
    );

  stim : process
    variable expected : std_logic_vector(63 downto 0);

    -- Reference requant (matches single-rounding MultiplyByQuantizedMultiplier)
    function ref_requant(acc, bias, mult, sh, off, mn, mx : integer)
      return std_logic_vector is
      variable x         : integer;
      variable total_sh  : integer;
      variable product   : signed(63 downto 0);
      variable rounded   : signed(63 downto 0);
      variable shifted   : signed(63 downto 0);
      variable result    : integer;
      variable rnd_bit   : signed(63 downto 0);
    begin
      x := acc + bias;
      total_sh := 31 - sh;
      product := to_signed(x, 32) * to_signed(mult, 32);
      rnd_bit := (others => '0');
      rnd_bit(total_sh - 1) := '1';
      rounded := product + rnd_bit;
      shifted := shift_right(rounded, total_sh);
      result := to_integer(shifted(31 downto 0)) + off;
      if result < mn then result := mn; end if;
      if result > mx then result := mx; end if;
      return std_logic_vector(resize(to_signed(result, 8), 64));
    end function;

    -- Fire a REQUANT operation: set all inputs + trigger in same cycle
    procedure fire_requant(
      acc  : integer;
      mult : integer;
      bias : integer;
      sh   : integer;
      off  : integer;
      mn   : integer;
      mx   : integer
    ) is
    begin
      operation <= OP_REQUANT;
      data_t1   <= std_logic_vector(to_signed(acc, 64));
      load_t1   <= '1';
      data_o1   <= pack_mult_bias(mult, bias);
      load_o1   <= '1';
      data_o2   <= pack_ctrl(sh, off, mn, mx);
      load_o2   <= '1';
      wait until rising_edge(clk);
      load_t1 <= '0';
      load_o1 <= '0';
      load_o2 <= '0';
    end procedure;

    procedure check_result(
      test_name : string;
      exp       : std_logic_vector(63 downto 0)
    ) is
    begin
      -- Pipeline: stage1_capture(0) → stage1_reg(1) → output_reg(2)
      -- fire_requant returns after cycle 0's rising edge.
      -- Wait for cycles 1 and 2, then a small delta for signal propagation.
      wait until rising_edge(clk);  -- cycle 1
      wait until rising_edge(clk);  -- cycle 2 (result registered here)
      wait for 1 ns;                -- delta for signal propagation
      test_count <= test_count + 1;
      if data_r1 = exp then
        pass_count <= pass_count + 1;
        report test_name & ": PASS" severity note;
      else
        report test_name & ": FAIL - expected " &
               integer'image(to_integer(signed(exp(7 downto 0)))) &
               " got " &
               integer'image(to_integer(signed(data_r1(7 downto 0))))
          severity error;
      end if;
    end procedure;

  begin
    -- Reset
    rstx <= '0';
    wait for CLK_PERIOD * 3;
    rstx <= '1';
    wait until rising_edge(clk);

    -- Test 1: Basic positive — acc=1000, bias=50, mult=1073741824 (0.5 in Q31),
    --         shift=-1 → total_shift=32, offset=0, clamp [-128,127]
    --   x = 1050, product = 1050 * 1073741824 = 1127428915200
    --   round = 1<<31 = 2147483648
    --   (product + round) >> 32 = (1127428915200 + 2147483648) >> 32 = 262 → clamped to 127
    fire_requant(1000, 1073741824, 50, -1, 0, -128, 127);
    expected := ref_requant(1000, 50, 1073741824, -1, 0, -128, 127);
    check_result("T1 basic positive", expected);

    -- Test 2: Negative accumulator — acc=-500, bias=100, mult=1500000000,
    --         shift=-3 → total_shift=34, offset=-10, clamp [-128,127]
    fire_requant(-500, 1500000000, 100, -3, -10, -128, 127);
    expected := ref_requant(-500, 100, 1500000000, -3, -10, -128, 127);
    check_result("T2 negative acc", expected);

    -- Test 3: Zero input
    fire_requant(0, 1073741824, 0, 0, 0, -128, 127);
    expected := ref_requant(0, 0, 1073741824, 0, 0, -128, 127);
    check_result("T3 zero input", expected);

    -- Test 4: Clamp to min
    fire_requant(-10000, 2000000000, -5000, -2, 0, -128, 127);
    expected := ref_requant(-10000, -5000, 2000000000, -2, 0, -128, 127);
    check_result("T4 clamp min", expected);

    -- Test 5: Clamp to max
    fire_requant(10000, 2000000000, 5000, -2, 0, -128, 127);
    expected := ref_requant(10000, 5000, 2000000000, -2, 0, -128, 127);
    check_result("T5 clamp max", expected);

    -- Test 6: Typical conv output (small values, realistic params)
    -- multiplier=1288490240 (~0.6 in Q31), shift=-5, offset=-128, clamp [0,255]
    fire_requant(200, 1288490240, 30, -5, -128, -128, 127);
    expected := ref_requant(200, 30, 1288490240, -5, -128, -128, 127);
    check_result("T6 typical conv", expected);

    -- Test 7: Large shift
    fire_requant(100, 1073741824, 0, -15, 0, -128, 127);
    expected := ref_requant(100, 0, 1073741824, -15, 0, -128, 127);
    check_result("T7 large shift", expected);

    -- Summary
    wait for CLK_PERIOD;
    report "REQUANT: " & integer'image(pass_count) & "/" &
           integer'image(test_count) & " PASS" severity note;
    assert pass_count = test_count
      report "REQUANT TESTBENCH FAILED" severity failure;

    sim_done <= true;
    wait;
  end process;

end architecture sim;
