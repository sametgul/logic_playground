----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 06/23/2026 05:35:11 PM
-- Design Name: 
-- Module Name: tb_lfsr - Behavioral
-- Project Name: 
-- Target Devices: 
-- Tool Versions: 
-- Description: 
-- 
-- Dependencies: 
-- 
-- Revision:
-- Revision 0.01 - File Created
-- Additional Comments:
-- 
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.all;

entity tb_lfsr is
	generic (
		DATA_WIDTH : integer := 10
	);
end tb_lfsr;

architecture Behavioral of tb_lfsr is
	signal clk      : std_logic := '0';
	signal enable_i : std_logic := '0';
	signal lfsr_o   : std_logic_vector(DATA_WIDTH - 1 downto 0);

	constant CLK_PRD : time := 10 ns;

begin

	p_CLKGEN : process
	begin
		clk <= '0';
		wait for CLK_PRD/2;
		clk <= '1';
		wait for CLK_PRD/2;

	end process;

	p_STIMULI : process begin
		wait for CLK_PRD * 5;
		enable_i <= '1';

		wait for CLK_PRD * 1050;
		enable_i <= '0';
		wait for CLK_PRD * 5;

		assert FALSE
		report "SIM DONE"
			severity failure;
	end process;

	inst_DUT : entity work.lfsr
		generic map(
			DATA_WIDTH => DATA_WIDTH,
			POLY_MASK  => "1001000000"
		)
		port map
		(
			clk      => clk,
			enable_i => enable_i,
			lfsr_o   => lfsr_o
		);

end Behavioral;
