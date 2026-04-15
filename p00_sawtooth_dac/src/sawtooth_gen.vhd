----------------------------------------------------------------------------------
-- Engineer:    Samet GUL
-- Email:       asam.gul@gmail.com
-- Github:      https://github.com/sametgul
-- LinkedIn:    www.linkedin.com/in/gul-samet
--
-- Create Date: 14.04.2026
-- Description: Sawtooth wave generator for PmodDA4.
--
-- Fires one DAC write per completed SPI transaction: detects the falling
-- edge of busy, increments a 12-bit counter, and pulses start for one cycle.
-- Natural 12-bit wraparound produces the sawtooth ramp.
-- Output frequency = 1 / (4096 * SPI_transaction_time).
-- busy_prev is initialised to '1' so the first write fires on power-on.
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;

entity sawtooth_gen is
  port (
    clk     : in std_logic;
    busy    : in std_logic; -- from PmodDA4
    dac_val : out std_logic_vector(11 downto 0);
    start   : out std_logic -- 1-cycle pulse to PmodDA4
  );
end sawtooth_gen;

architecture Behavioral of sawtooth_gen is

  signal val : unsigned(11 downto 0) := (others => '0');

  signal busy_prev : STD_LOGIC := '1';

begin

  dac_val <= std_logic_vector(val);

  process (clk) begin
    if rising_edge(clk) then
      start <= '0';
      if busy = '0' and busy_prev = '1' then
        val   <= val + 1;
        start <= '1';
      end if;
      busy_prev <= busy;
    end if;
  end process;

end Behavioral;
