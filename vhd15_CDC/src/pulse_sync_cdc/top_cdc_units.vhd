----------------------------------------------------------------------------------
-- Engineer: Samet GUL
-- 
-- Create Date: 25.07.2026 21:54:00
--
-- Description: 
-- 
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.all;

entity top_cdc_units is
  port (
    -- external interface
    clka      : in std_logic;
    clkb      : in std_logic;
    rst       : in std_logic := '0';
    number1_i : in std_logic_vector(7 downto 0);
    number2_i : in std_logic_vector(7 downto 0);
    sum_o     : out std_logic_vector(7 downto 0);
    enable    : in std_logic;
    ready     : out std_logic
  );

end top_cdc_units;

architecture Behavioral of top_cdc_units is

  -- unit 2 interface
  signal number1_12 : std_logic_vector(7 downto 0);
  signal number2_12 : std_logic_vector(7 downto 0);
  signal sum_21     : std_logic_vector(7 downto 0) := (others => '0');

  signal pulse_unit1_i : std_logic := '0';
  signal pulse_unit1_o : std_logic := '0';
  signal pulse_unit2_i : std_logic := '0';
  signal pulse_unit2_o : std_logic := '0';

begin

  inst_unit1 : entity work.unit1
    port map
    (
      -- external interface
      clka      => clka,
      number1_i => number1_i,
      number2_i => number2_i,
      sum_o     => sum_o,
      enable    => enable,
      ready     => ready,

      -- unit 2 interface
      number1_o => number1_12,
      number2_o => number2_12,
      sum_i     => sum_21,
      pulse_b_i => pulse_unit1_i,
      pulse_a_o => pulse_unit1_o
    );

  inst_unit2 : entity work.unit2
    port map
    (
      clkb      => clkb,
      number1_i => number1_12,
      number2_i => number2_12,
      sum_o     => sum_21,
      pulse_b_i => pulse_unit2_i,
      pulse_a_o => pulse_unit2_o
    );

  inst_cdc_unit12 : entity work.cdc_pulse_sync
    generic map(
      N => 3
    )
    port map
    (
      clka    => clka,
      clkb    => clkb,
      rst     => rst,
      pulse_a => pulse_unit1_o,
      pulse_b => pulse_unit2_i
    );

  inst_cdc_unit21 : entity work.cdc_pulse_sync
    generic map(
      N => 3
    )
    port map
    (
      clka    => clkb,
      clkb    => clka,
      rst     => rst,
      pulse_a => pulse_unit2_o,
      pulse_b => pulse_unit1_i
    );

end Behavioral;
