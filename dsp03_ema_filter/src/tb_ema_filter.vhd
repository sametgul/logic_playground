library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;

-- Smoke test: drives a constant step and checks the converged output against
-- the exact value from models/ema_fixed.py (see that computation in the
-- README/commit message). Not the full bit-exact random-stall testbench
-- (that's the dedicated "bit-exact simulation" step) - this just confirms
-- the VHDL implements the same algorithm as the Python golden model.
entity tb_ema_filter is
end tb_ema_filter;

architecture behavioral of tb_ema_filter is
	constant INT_BITS    : integer := 2;
	constant FRAC_BITS   : integer := 15;
	constant GUARD_BITS  : integer := 0;
	constant DATA_WIDTH  : integer := INT_BITS + FRAC_BITS;
	constant ALPHA_WIDTH : integer := FRAC_BITS + GUARD_BITS;

	constant CLK_PERIOD : time := 10 ns;
	signal clk : std_logic := '0';
	signal rst : std_logic := '1';

	-- alpha for Ts=1e-3, tau=1e-2 (from ema_float.alpha_from_tau), quantized to unsigned Q0.15
	signal alpha_i : std_logic_vector(ALPHA_WIDTH - 1 downto 0) := std_logic_vector(to_unsigned(3118, ALPHA_WIDTH));

	signal s_axis_tvalid : std_logic := '0';
	signal s_axis_tready : std_logic;
	-- x = 1.0 at Q2.15
	signal s_axis_tdata : std_logic_vector(DATA_WIDTH - 1 downto 0) := std_logic_vector(to_signed(32768, DATA_WIDTH));

	signal m_axis_tvalid : std_logic;
	signal m_axis_tready : std_logic := '1';
	signal m_axis_tdata  : std_logic_vector(DATA_WIDTH - 1 downto 0);
begin

	dut : entity work.ema_filter
		generic map(
			INT_BITS   => INT_BITS,
			FRAC_BITS  => FRAC_BITS,
			GUARD_BITS => GUARD_BITS
		)
		port map(
			clk           => clk,
			rst           => rst,
			alpha_i       => alpha_i,
			s_axis_tvalid => s_axis_tvalid,
			s_axis_tready => s_axis_tready,
			s_axis_tdata  => s_axis_tdata,
			m_axis_tvalid => m_axis_tvalid,
			m_axis_tready => m_axis_tready,
			m_axis_tdata  => m_axis_tdata
		);

	pCLK_GEN : process begin
		clk <= '0'; wait for CLK_PERIOD / 2;
		clk <= '1'; wait for CLK_PERIOD / 2;
	end process;

	pSTIMULI : process
		variable final_code : integer;
		-- from ema_fixed.py: ema_filter_fixed(x=ones(200), alpha, int_bits=2, frac_bits=15, guard_bits=0)[-1] * 2**15
		constant EXPECTED_CODE : integer := 32763;
		-- covers the round-half-up (VHDL) vs round-half-away-from-zero (Python) tie-breaking
		-- difference - a known, documented gotcha, not slack for an actual bug
		constant TOLERANCE : integer := 4;
	begin
		wait for CLK_PERIOD * 3;
		rst <= '0';
		wait until falling_edge(clk);

		s_axis_tvalid <= '1';
		for i in 1 to 200 loop
			wait until falling_edge(clk);
		end loop;
		wait until falling_edge(clk);

		final_code := to_integer(signed(m_axis_tdata));
		report "final output code = " & integer'image(final_code) & " (expected ~" & integer'image(EXPECTED_CODE) & ")";

		assert abs(final_code - EXPECTED_CODE) <= TOLERANCE
			report "EMA filter output mismatch vs Python golden model" severity failure;

		report "PASS: matches Python golden model within tolerance" severity note;
		assert false report "SIM DONE" severity failure;
	end process;

end behavioral;
