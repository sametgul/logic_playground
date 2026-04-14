----------------------------------------------------------------------------------
-- Engineer:    Samet GUL
-- Create Date: 14.04.2026
-- Description: Timer-based sawtooth wave generator for PmodDA4
--
-- Generates a 12-bit linear ramp at SAW_FREQ Hz.
-- Timer pauses while busy='1' so no samples are skipped.
-- One PERIOD = CLK_FREQ / (SAW_FREQ * 4096) clock cycles per DAC step.
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;

entity sawtooth_gen is
  generic (
    CLK_FREQ : integer := 100_000_000; -- system clock frequency (Hz)
    SAW_FREQ : integer := 100          -- sawtooth frequency (Hz)
  );
  port (
    clk     : in  std_logic;
    busy    : in  std_logic;           -- from PmodDA4: pauses timer while high
    dac_val : out std_logic_vector(11 downto 0);
    start   : out std_logic            -- 1-cycle pulse to PmodDA4
  );
end sawtooth_gen;

architecture Behavioral of sawtooth_gen is

  constant PERIOD : integer := CLK_FREQ / (SAW_FREQ * 4096);

  signal timer : integer range 0 to PERIOD - 1 := 0;
  signal val   : unsigned(11 downto 0)          := (others => '0');

begin

  dac_val <= std_logic_vector(val);

  process (clk) begin
    if rising_edge(clk) then
      start <= '0';
      if busy = '0' then
        if timer = PERIOD - 1 then
          timer <= 0;
          val   <= val + 1;
          start <= '1';
        else
          timer <= timer + 1;
        end if;
      end if;
    end if;
  end process;

end Behavioral;
