library IEEE;
use IEEE.STD_LOGIC_1164.all;

entity lfsr_handwritten is
	generic (
		DATA_WIDTH : integer := 10;
		-- Mask for the x^10 + x^7 + 1 polynomial (10th and 7th bits are '1')
		POLY_MASK : std_logic_vector := "1001000000"
	);
	port (
		clk      : in std_logic;
		rst      : in std_logic;
		enable_i : in std_logic;
		lfsr_o   : out std_logic_vector(DATA_WIDTH - 1 downto 0)
	);
end lfsr_handwritten;

architecture behavioral of lfsr_handwritten is
	-- Seed has a single '1' at the MSB. POLY_MASK must also have a '1' at that same index,
	-- otherwise every AND in the feedback loop is '0' and the LFSR locks up at all-zero forever.
	signal data_r : std_logic_vector(DATA_WIDTH - 1 downto 0) := '1' & (DATA_WIDTH - 2 downto 0 => '0');
begin
	process (clk)
		variable xor_feedback_v : std_logic;
	begin
		if rising_edge(clk) then
			if rst = '1' then
				data_r <= '1' & (DATA_WIDTH - 2 downto 0 => '0');
			elsif enable_i = '1' then
				xor_feedback_v := '0';

				-- We are only interested in the element of data_r that match with the 1s of POLY_MASK, so we AND them
				-- then, since 0s are useless in XOR operations only 1s of the output of AND operation will affect the
				-- XOR operation
				for i in 0 to DATA_WIDTH - 1 loop
					xor_feedback_v := (data_r(i) and POLY_MASK(i)) xor xor_feedback_v;
				end loop;

				data_r(DATA_WIDTH - 1 downto 0) <= data_r(DATA_WIDTH - 2 downto 0) & xor_feedback_v;
			end if;
		end if;
	end process;

	lfsr_o <= data_r;
end behavioral;
