library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

library STD;
use std.env.all;

library uvvm_util;
context uvvm_util.uvvm_util_context;

library bitvis_vip_sbi;
use bitvis_vip_sbi.sbi_bfm_pkg.all;
-- Test case entity
entity tb_debouncer_uvvm is
	generic (
		CLK_FREQ   : integer := 1000; -- Hz
		DEBTIME_MS : integer := 5;    -- ms
		ACTIVE_LOW : boolean := true
	);
end entity tb_debouncer_uvvm;

architecture func of tb_debouncer_uvvm is
	constant C_CLK_PERIOD : time      := 1 ms;
	signal clk            : std_logic := '0';

	signal clock_ena : boolean := false;

	signal sig_in  : std_logic := '1';
	signal sig_out : std_logic;
begin

	-----------------------------------------------------------------------------
	-- Clock Generator
	-----------------------------------------------------------------------------
	clock_generator(clk, clock_ena, C_CLK_PERIOD, "Debouncer TB clock");

	-----------------------------------------------------------------------------
	-- Instantiate DUT
	-----------------------------------------------------------------------------
	DUT : entity work.debouncer
		generic map(
			CLK_FREQ   => CLK_FREQ,
			DEBTIME_MS => DEBTIME_MS,
			ACTIVE_LOW => ACTIVE_LOW
		)
		port map
		(
			clk     => clk,
			sig_in  => sig_in,
			sig_out => sig_out
		);

	------------------------------------------------
	-- PROCESS: p_main
	------------------------------------------------
	p_main : process
		constant C_SCOPE : string := C_TB_SCOPE_DEFAULT;

	begin

		-- Print the configuration to the log
		report_global_ctrl(VOID);
		report_msg_id_panel(VOID);

		enable_log_msg(ALL_MESSAGES);
		--disable_log_msg(ALL_MESSAGES);
		--enable_log_msg(ID_LOG_HDR);

		log(ID_LOG_HDR, "Start Simulation of TB for Debouncer", C_SCOPE);
		set_alert_stop_limit(ERROR, 0); -- 0 = never stop on ERROR, keep running

		------------------------------------------------------------
		clock_ena <= true; -- to start clock generator

		--==================================================================================================
		-- Stimulus and checks (timeline in ms, DEBTIME_MS = 5)
		--------------------------------------------------------------------------------------
		-- Idle: input released, output must be inactive-high
		wait for 2 ms;
		check_value(sig_out, '1', ERROR, "Output idle high after startup", C_SCOPE);

		-- Glitch: 3 ms press (shorter than debounce time) must be rejected
		wait for 3 ms;
		sig_in <= '0';
		wait for 3 ms;
		sig_in <= '1';
		wait for 1 ms;
		check_value(sig_out, '1', ERROR, "3 ms glitch rejected", C_SCOPE);

		-- Real press: 10 ms low must be accepted after the debounce time
		wait for 1 ms;
		sig_in <= '0';
		wait for 2 ms;
		check_value(sig_out, '1', ERROR, "Output still high before debounce time elapsed", C_SCOPE);
		wait for 6 ms;
		check_value(sig_out, '0', ERROR, "Press accepted after debounce time", C_SCOPE);

		-- Release: output must return high only after the debounce time
		wait for 2 ms;
		sig_in <= '1';
		wait for 2 ms;
		check_value(sig_out, '0', ERROR, "Output still low before release debounced", C_SCOPE);
		wait for 6 ms;
		check_value(sig_out, '1', ERROR, "Release accepted after debounce time", C_SCOPE);

		sig_in <= '0';
		await_value(sig_out, '0', 4 ms, 7 ms, ERROR, "Press debounced within window", C_SCOPE);

		wait for 2 ms;
		report_alert_counters(FINAL); -- Report final counters and print conclusion for simulation (Success/Fail)
		log(ID_LOG_HDR, "SIMULATION COMPLETED", C_SCOPE);

		-- Finish the simulation
		std.env.stop;
		wait; -- to stop completely

	end process p_main;
end architecture;
