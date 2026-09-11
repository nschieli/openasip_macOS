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

entity tb_emac2x32 is
end entity tb_emac2x32;

architecture sim of tb_emac2x32 is

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

  constant OP_EMAC2X32 : std_logic_vector(1 downto 0) := "11";

  signal test_count : integer := 0;
  signal pass_count : integer := 0;

begin

  clk <= not clk after CLK_PERIOD / 2 when not sim_done else '0';

  dut : entity work.ecp5_mul64_requant_pipelined
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
    -- Reference: compute emac2x32 result
    function ref_emac2x32(
      acc_lo, acc_hi : integer;
      filter_0, filter_1 : integer;
      input_0, input_1 : integer;
      offset : integer
    ) return std_logic_vector is
      variable new_lo : integer;
      variable new_hi : integer;
      variable r : std_logic_vector(63 downto 0);
    begin
      new_lo := acc_lo + filter_0 * (input_0 + offset);
      new_hi := acc_hi + filter_1 * (input_1 + offset);
      r(31 downto 0) := std_logic_vector(to_signed(new_lo, 32));
      r(63 downto 32) := std_logic_vector(to_signed(new_hi, 32));
      return r;
    end function;

    -- Pack in2: {offset[63:32], filter_1[15:8], filter_0[7:0]}
    function pack_in2(offset, f1, f0 : integer) return std_logic_vector is
      variable r : std_logic_vector(63 downto 0);
    begin
      r := (others => '0');
      r(7 downto 0) := std_logic_vector(to_signed(f0, 8));
      r(15 downto 8) := std_logic_vector(to_signed(f1, 8));
      r(63 downto 32) := std_logic_vector(to_signed(offset, 32));
      return r;
    end function;

    -- Pack in3: {input_1[15:8], input_0[7:0]}
    function pack_in3(i1, i0 : integer) return std_logic_vector is
      variable r : std_logic_vector(63 downto 0);
    begin
      r := (others => '0');
      r(7 downto 0) := std_logic_vector(to_signed(i0, 8));
      r(15 downto 8) := std_logic_vector(to_signed(i1, 8));
      return r;
    end function;

    -- Pack acc: {acc_hi[63:32], acc_lo[31:0]}
    function pack_acc(hi, lo : integer) return std_logic_vector is
      variable r : std_logic_vector(63 downto 0);
    begin
      r(31 downto 0) := std_logic_vector(to_signed(lo, 32));
      r(63 downto 32) := std_logic_vector(to_signed(hi, 32));
      return r;
    end function;

    procedure fire(acc_lo, acc_hi, f0, f1, i0, i1, off : integer) is
    begin
      operation <= OP_EMAC2X32;
      data_t1 <= pack_acc(acc_hi, acc_lo);
      load_t1 <= '1';
      data_o1 <= pack_in2(off, f1, f0);
      load_o1 <= '1';
      data_o2 <= pack_in3(i1, i0);
      load_o2 <= '1';
      wait until rising_edge(clk);
      load_t1 <= '0'; load_o1 <= '0'; load_o2 <= '0';
    end procedure;

    procedure check(name : string; exp : std_logic_vector(63 downto 0)) is
    begin
      wait until rising_edge(clk);
      wait until rising_edge(clk);
      wait for 1 ns;
      test_count <= test_count + 1;
      if data_r1 = exp then
        pass_count <= pass_count + 1;
        report name & ": PASS" severity note;
      else
        report name & ": FAIL - expected lo=" &
               integer'image(to_integer(signed(exp(31 downto 0)))) &
               " hi=" & integer'image(to_integer(signed(exp(63 downto 32)))) &
               " got lo=" & integer'image(to_integer(signed(data_r1(31 downto 0)))) &
               " hi=" & integer'image(to_integer(signed(data_r1(63 downto 32))))
          severity error;
      end if;
    end procedure;

    variable expected : std_logic_vector(63 downto 0);

  begin
    rstx <= '0';
    wait for CLK_PERIOD * 3;
    rstx <= '1';
    wait until rising_edge(clk);

    -- T1: Simple positive, no offset
    -- acc=0, f={2,3}, i={4,5}, off=0 -> lo=2*4=8, hi=3*5=15
    fire(0, 0, 2, 3, 4, 5, 0);
    expected := ref_emac2x32(0, 0, 2, 3, 4, 5, 0);
    check("T1 simple positive", expected);

    -- T2: With offset
    -- acc=0, f={1,1}, i={10,20}, off=-128 -> lo=1*(10-128)=-118, hi=1*(20-128)=-108
    fire(0, 0, 1, 1, 10, 20, -128);
    expected := ref_emac2x32(0, 0, 1, 1, 10, 20, -128);
    check("T2 with offset", expected);

    -- T3: Accumulate (non-zero starting acc)
    -- acc={100, 200}, f={-5, 10}, i={3, -7}, off=0
    fire(100, 200, -5, 10, 3, -7, 0);
    expected := ref_emac2x32(100, 200, -5, 10, 3, -7, 0);
    check("T3 accumulate", expected);

    -- T4: Negative filter and input
    fire(0, 0, -127, -128, -128, 127, 0);
    expected := ref_emac2x32(0, 0, -127, -128, -128, 127, 0);
    check("T4 negatives", expected);

    -- T5: Large offset (typical quantization)
    fire(0, 0, 50, -50, 100, -100, -128);
    expected := ref_emac2x32(0, 0, 50, -50, 100, -100, -128);
    check("T5 large offset", expected);

    -- T6: Accumulator overflow check (large values)
    fire(2000000000, -2000000000, 127, 127, 127, 127, 0);
    expected := ref_emac2x32(2000000000, -2000000000, 127, 127, 127, 127, 0);
    check("T6 large acc", expected);

    -- T7: Zero filter (should not change acc)
    fire(42, 99, 0, 0, 100, 100, -128);
    expected := ref_emac2x32(42, 99, 0, 0, 100, 100, -128);
    check("T7 zero filter", expected);

    -- Summary
    wait for CLK_PERIOD;
    report "EMAC2X32: " & integer'image(pass_count) & "/" &
           integer'image(test_count) & " PASS" severity note;
    assert pass_count = test_count
      report "EMAC2X32 TESTBENCH FAILED" severity failure;

    sim_done <= true;
    wait;
  end process;

end architecture sim;
