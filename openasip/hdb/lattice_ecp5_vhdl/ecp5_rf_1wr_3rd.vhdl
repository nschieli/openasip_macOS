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

use work.tce_util.all;

entity ecp5_rf_1wr_3rd is
  generic (
    width_g : integer;
    depth_g : integer);
  port (
    clk           : in  std_logic;
    rstx          : in  std_logic;
    glock_in      : in  std_logic;

    -- Read port A
    load_rd_a_in  : in  std_logic;
    data_rd_a_out : out std_logic_vector(width_g-1 downto 0);
    addr_rd_a_in  : in  std_logic_vector(bit_width(depth_g)-1 downto 0);

    -- Read port B
    load_rd_b_in  : in  std_logic;
    data_rd_b_out : out std_logic_vector(width_g-1 downto 0);
    addr_rd_b_in  : in  std_logic_vector(bit_width(depth_g)-1 downto 0);

    -- Read port C
    load_rd_c_in  : in  std_logic;
    data_rd_c_out : out std_logic_vector(width_g-1 downto 0);
    addr_rd_c_in  : in  std_logic_vector(bit_width(depth_g)-1 downto 0);

    -- Write port
    load_wr_in    : in  std_logic;
    data_wr_in    : in  std_logic_vector(width_g-1 downto 0);
    addr_wr_in    : in  std_logic_vector(bit_width(depth_g)-1 downto 0)
  );
end entity ecp5_rf_1wr_3rd;

architecture rtl of ecp5_rf_1wr_3rd is

  type ram_type is array (0 to depth_g-1) of std_logic_vector(width_g-1 downto 0);

  -- Three RAM copies: one per read port (all written simultaneously)
  signal ram_a : ram_type := (others => (others => '0'));
  signal ram_b : ram_type := (others => (others => '0'));
  signal ram_c : ram_type := (others => (others => '0'));

  -- Registered read outputs (synchronous = BRAM-compatible)
  signal rd_data_a_r : std_logic_vector(width_g-1 downto 0) := (others => '0');
  signal rd_data_b_r : std_logic_vector(width_g-1 downto 0) := (others => '0');
  signal rd_data_c_r : std_logic_vector(width_g-1 downto 0) := (others => '0');

  -- Write-forwarding detection
  signal wr_fwd_a_r  : std_logic := '0';
  signal wr_fwd_b_r  : std_logic := '0';
  signal wr_fwd_c_r  : std_logic := '0';
  signal wr_data_r   : std_logic_vector(width_g-1 downto 0) := (others => '0');

begin

  -- RAM A: write + synchronous read for port A
  ram_a_proc : process(clk)
  begin
    if rising_edge(clk) then
      if glock_in = '0' then
        if load_wr_in = '1' then
          ram_a(to_integer(unsigned(addr_wr_in))) <= data_wr_in;
        end if;
        rd_data_a_r <= ram_a(to_integer(unsigned(addr_rd_a_in)));
      end if;
    end if;
  end process;

  -- RAM B: write + synchronous read for port B
  ram_b_proc : process(clk)
  begin
    if rising_edge(clk) then
      if glock_in = '0' then
        if load_wr_in = '1' then
          ram_b(to_integer(unsigned(addr_wr_in))) <= data_wr_in;
        end if;
        rd_data_b_r <= ram_b(to_integer(unsigned(addr_rd_b_in)));
      end if;
    end if;
  end process;

  -- RAM C: write + synchronous read for port C
  ram_c_proc : process(clk)
  begin
    if rising_edge(clk) then
      if glock_in = '0' then
        if load_wr_in = '1' then
          ram_c(to_integer(unsigned(addr_wr_in))) <= data_wr_in;
        end if;
        rd_data_c_r <= ram_c(to_integer(unsigned(addr_rd_c_in)));
      end if;
    end if;
  end process;

  -- Write-forwarding: detect same-cycle read-after-write
  fwd_proc : process(clk)
  begin
    if rising_edge(clk) then
      if glock_in = '0' then
        wr_data_r <= data_wr_in;

        if load_wr_in = '1' and addr_wr_in = addr_rd_a_in then
          wr_fwd_a_r <= '1';
        else
          wr_fwd_a_r <= '0';
        end if;

        if load_wr_in = '1' and addr_wr_in = addr_rd_b_in then
          wr_fwd_b_r <= '1';
        else
          wr_fwd_b_r <= '0';
        end if;

        if load_wr_in = '1' and addr_wr_in = addr_rd_c_in then
          wr_fwd_c_r <= '1';
        else
          wr_fwd_c_r <= '0';
        end if;
      end if;
    end if;
  end process;

  -- Output mux: forwarded write data or BRAM read data
  data_rd_a_out <= wr_data_r when wr_fwd_a_r = '1' else rd_data_a_r;
  data_rd_b_out <= wr_data_r when wr_fwd_b_r = '1' else rd_data_b_r;
  data_rd_c_out <= wr_data_r when wr_fwd_c_r = '1' else rd_data_c_r;

end architecture rtl;
