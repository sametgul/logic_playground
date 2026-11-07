library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;

-- Reproduces CLAUDE.md's hardware note directly in VHDL (mirrors
-- test_tiny_alpha_stalls_without_guard_bits / test_guard_bits_fix_the_stall
-- in models/test_ema_fixed.py): tau=1s at 1 MSa/s makes alpha so tiny it's
-- not even representable at 15 fractional bits (alpha_code=0 there), so the
-- filter must stall without guard bits, and must not stall with them.
entity tb_ema_filter_guard_bits is
end tb_ema_filter_guard_bits;

architecture behavioral of tb_ema_filter_guard_bits is
	constant INT_BITS  : integer := 2; -- INT_BITS=1 can't represent x=1.0 (range is only [-1, 0.99997)); caught via GHDL's "vector truncated" warning
	constant FRAC_BITS : integer := 15;
	constant DATA_WIDTH : integer := INT_BITS + FRAC_BITS;

	constant CLK_PERIOD : time := 10 ns;
	signal clk : std_logic := '0';
	signal rst : std_logic := '1';

	signal s_axis_tvalid : std_logic := '0';
	constant s_axis_tdata : std_logic_vector(DATA_WIDTH - 1 downto 0) := std_logic_vector(to_signed(32768, DATA_WIDTH)); -- x=1.0

	-- no guard bits: alpha=1e-6 rounds to code 0 at 15 bits, every increment is zero
	constant ALPHA_WIDTH_STALLED : integer := FRAC_BITS + 0;
	signal alpha_i_stalled  : std_logic_vector(ALPHA_WIDTH_STALLED - 1 downto 0) := std_logic_vector(to_unsigned(0, ALPHA_WIDTH_STALLED));
	signal tready_stalled   : std_logic;
	signal tvalid_o_stalled : std_logic;
	signal tdata_o_stalled  : std_logic_vector(DATA_WIDTH - 1 downto 0);

	-- 20 guard bits: enough precision that alpha is representable and the filter moves
	constant ALPHA_WIDTH_FIXED : integer := FRAC_BITS + 20;
	signal alpha_i_fixed  : std_logic_vector(ALPHA_WIDTH_FIXED - 1 downto 0) := std_logic_vector(to_unsigned(34360, ALPHA_WIDTH_FIXED));
	signal tready_fixed   : std_logic;
	signal tvalid_o_fixed : std_logic;
	signal tdata_o_fixed  : std_logic_vector(DATA_WIDTH - 1 downto 0);
begin

	dut_stalled : entity work.ema_filter
		generic map(INT_BITS => INT_BITS, FRAC_BITS => FRAC_BITS, GUARD_BITS => 0)
		port map(
			clk => clk, rst => rst,
			alpha_i => alpha_i_stalled,
			s_axis_tvalid => s_axis_tvalid, s_axis_tready => tready_stalled, s_axis_tdata => s_axis_tdata,
			m_axis_tvalid => tvalid_o_stalled, m_axis_tready => '1', m_axis_tdata => tdata_o_stalled
		);

	dut_fixed : entity work.ema_filter
		generic map(INT_BITS => INT_BITS, FRAC_BITS => FRAC_BITS, GUARD_BITS => 20)
		port map(
			clk => clk, rst => rst,
			alpha_i => alpha_i_fixed,
			s_axis_tvalid => s_axis_tvalid, s_axis_tready => tready_fixed, s_axis_tdata => s_axis_tdata,
			m_axis_tvalid => tvalid_o_fixed, m_axis_tready => '1', m_axis_tdata => tdata_o_fixed
		);

	pCLK_GEN : process begin
		clk <= '0'; wait for CLK_PERIOD / 2;
		clk <= '1'; wait for CLK_PERIOD / 2;
	end process;

	pSTIMULI : process
		variable stalled_code : integer;
		variable fixed_code   : integer;
	begin
		wait for CLK_PERIOD * 3;
		rst <= '0';
		wait until falling_edge(clk);

		s_axis_tvalid <= '1';
		for i in 1 to 2000 loop
			wait until falling_edge(clk);
		end loop;
		wait until falling_edge(clk);

		stalled_code := to_integer(signed(tdata_o_stalled));
		fixed_code   := to_integer(signed(tdata_o_fixed));
		report "guard_bits=0  output code = " & integer'image(stalled_code) & " (expect 0: stalled)";
		report "guard_bits=20 output code = " & integer'image(fixed_code) & " (expect >0: moving)";

		assert stalled_code = 0
			report "expected the no-guard-bits case to be stalled at 0" severity failure;
		assert fixed_code > 0
			report "expected the guard_bits=20 case to have moved off zero" severity failure;

		report "PASS: guard bits reproduce the hardware problem and its fix" severity note;
		assert false report "SIM DONE" severity failure;
	end process;

end behavioral;
