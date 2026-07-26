----------------------------------------------------------------------------------
-- Company: 
-- Engineer: Samet GUL
-- 
-- Create Date: 25.07.2026 20:57:42
-- 
-- Description: Testbench for the cdc pulse synchronizer module
-- 
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.all;

entity tb_cdc_pulse is
end tb_cdc_pulse;

architecture Behavioral of tb_cdc_pulse is

  signal clka    : std_logic := '0';
  signal clkb    : std_logic := '0';
  signal pulse_a : std_logic := '0';
  signal pulse_b : std_logic;

  --constant CLK_A_PERIOD : time := 10 ns; -- Clock A period
  --constant CLK_B_PERIOD : time := 7.5 ns; -- Clock B period

  constant CLK_A_PERIOD : time := 7.5 ns; -- Clock A period
  constant CLK_B_PERIOD : time := 10 ns; -- Clock B period

begin

  p_STIMULI : process
  begin
    -- Generate a pulse on pulse_a
    wait for CLK_A_PERIOD * 2;
    pulse_a <= '1';
    wait for CLK_A_PERIOD;
    pulse_a <= '0';
    wait for CLK_A_PERIOD;
    pulse_a <= '1';
    wait for CLK_A_PERIOD;
    pulse_a <= '0';
    wait for CLK_A_PERIOD;
    pulse_a <= '1';
    wait for CLK_A_PERIOD;
    pulse_a <= '0';
    wait for CLK_A_PERIOD * 10;

    assert false report "Simulation finished" severity failure;
  end process;

  p_CLK_A : process
  begin
    clka <= '0';
    wait for CLK_A_PERIOD / 2;
    clka <= '1';
    wait for CLK_A_PERIOD / 2;
  end process;

  p_CLK_B : process
  begin
    clkb <= '0';
    wait for CLK_B_PERIOD / 2;
    clkb <= '1';
    wait for CLK_B_PERIOD / 2;
  end process;

  inst_DUT : entity work.cdc_pulse_sync
    generic map(
      N => 3
    )
    port map
    (
      clka    => clka,
      clkb    => clkb,
      pulse_a => pulse_a,
      pulse_b => pulse_b
    );

end Behavioral;
