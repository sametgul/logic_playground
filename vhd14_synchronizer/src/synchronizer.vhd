----------------------------------------------------------------------------------
-- Engineer: Samet GUL
-- Create Date: 23.07.2026 21:30
-- Description: This is a generic synchronizer module
-- that synchronizes an asynchronous input signal to a clock domain.
-- The number of flip-flops used for synchronization can be configured
-- using the generic parameter N.
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity synchronizer is
generic (
    N : integer := 3
);
Port (
clk 	: in STD_LOGIC;
async_in 	: in STD_LOGIC;
sync_out 	: out STD_LOGIC
);
end synchronizer;

architecture Behavioral of synchronizer is

signal sync_ff	: std_logic_vector (N-1 downto 0) := (others => '0');
attribute ASYNC_REG : string;
attribute ASYNC_REG of sync_ff : signal is "TRUE";

begin

process (clk) begin
if (rising_edge(clk)) then

	sync_ff	<= sync_ff(sync_ff'left-1 downto 0) & async_in;

end if;
end process;

sync_out	<= sync_ff(sync_ff'left);

end Behavioral;
