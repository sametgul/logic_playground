----------------------------------------------------------------------------------
-- Engineer: Samet GUL
-- 
-- Create Date: 25.07.2026 12:57:17
--
-- Description: This is a pulse synchronizer module that 
-- synchronizes a pulse signal from one clock domain to another.
-- It uses a chain of flip-flops to mitigate metastability issues 
-- when transferring signals between different clock domains.
-- 
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.all;

entity cdc_pulse_sync is
  generic (
    N : integer := 3 -- Number of flip-flops in the synchronizer chain
  );
  port (
    clka    : in std_logic;
    clkb    : in std_logic;
    rst     : in std_logic := '0'; -- async, active-high; held/released independently per domain
    pulse_a : in std_logic;
    pulse_b : out std_logic
  );
end cdc_pulse_sync;

architecture Behavioral of cdc_pulse_sync is

  signal sync_chain     : std_logic_vector(N - 1 downto 0) := (others => '0');
  signal pulse_a_toggle : std_logic                        := '0';

  -- Reset synchronizer: async-assert / sync-deassert, one per clock domain
  signal rst_a_meta, rst_a_sync : std_logic := '1';
  signal rst_b_meta, rst_b_sync : std_logic := '1';

  attribute ASYNC_REG                                                     : string;
  attribute ASYNC_REG of sync_chain                                       : signal is "TRUE";
  attribute ASYNC_REG of rst_a_meta, rst_a_sync, rst_b_meta, rst_b_sync   : signal is "TRUE";

begin

  -- rst is asserted immediately (no clock needed); its release is
  -- re-synchronized into each domain so it can never violate recovery/removal
  -- timing on the flops it feeds.
  process (clka, rst)
  begin
    if rst = '1' then
      rst_a_meta <= '1';
      rst_a_sync <= '1';
    elsif rising_edge(clka) then
      rst_a_meta <= '0';
      rst_a_sync <= rst_a_meta;
    end if;
  end process;

  process (clkb, rst)
  begin
    if rst = '1' then
      rst_b_meta <= '1';
      rst_b_sync <= '1';
    elsif rising_edge(clkb) then
      rst_b_meta <= '0';
      rst_b_sync <= rst_b_meta;
    end if;
  end process;

  process (clka, rst_a_sync)
  begin
    if rst_a_sync = '1' then
      pulse_a_toggle <= '0';
    elsif rising_edge(clka) then
      pulse_a_toggle <= pulse_a_toggle xor pulse_a; -- Toggle on pulse_a
    end if;
  end process;

  process (clkb, rst_b_sync)
  begin
    if rst_b_sync = '1' then
      sync_chain <= (others => '0');
      pulse_b    <= '0';
    elsif rising_edge(clkb) then
      sync_chain(0)              <= pulse_a_toggle; -- Capture the toggle signal in the first flip-flop
      sync_chain(N - 1 downto 1) <= sync_chain(N - 2 downto 0); -- Shift the chain
      pulse_b                    <= sync_chain(N - 1) xor sync_chain(N - 2); -- Generate pulse_b on the rising edge of the toggle
    end if;
  end process;

end Behavioral;
