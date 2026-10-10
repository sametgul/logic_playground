library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

library STD;
use std.env.all;

library uvvm_util;
context uvvm_util.uvvm_util_context;

-- Test case entity
entity tb_lfsr_uvvm is
end entity tb_lfsr_uvvm;

architecture func of tb_lfsr_uvvm is
	constant C_CLK_PERIOD : time    := 10 ns;
	constant C_WIDTH      : natural := 10;
	constant C_PERIOD     : natural := 2 ** C_WIDTH - 1; -- m-sequence length: 1023
	-- x^10 + x^7 + 1, same polynomial as the DUT default
	constant C_POLY_MASK : std_logic_vector(C_WIDTH - 1 downto 0) := "1001000000";
	-- DUT powers up with a single '1' at the MSB
	constant C_SEED : std_logic_vector(C_WIDTH - 1 downto 0) := "1000000000";

	signal clk       : std_logic := '0';
	signal clock_ena : boolean   := false;

	signal enable_i : std_logic := '0';
	signal lfsr_o   : std_logic_vector(C_WIDTH - 1 downto 0);

	-- Reference model for one LFSR step: feedback = bit 9 xor bit 6, shifted into bit 0
	function next_state(s : std_logic_vector(C_WIDTH - 1 downto 0)) return std_logic_vector is
	begin
		return s(C_WIDTH - 2 downto 0) & (s(9) xor s(6));
	end function;

begin

	-----------------------------------------------------------------------------
	-- Clock Generator
	-----------------------------------------------------------------------------
	clock_generator(clk, clock_ena, C_CLK_PERIOD, "LFSR TB clock");

	-----------------------------------------------------------------------------
	-- Instantiate DUT
	-----------------------------------------------------------------------------
	DUT : entity work.lfsr
		generic map(
			DATA_WIDTH => C_WIDTH,
			POLY_MASK  => C_POLY_MASK
		)
		port map
		(
			clk      => clk,
			enable_i => enable_i,
			lfsr_o   => lfsr_o
		);

	------------------------------------------------
	-- PROCESS: p_main
	------------------------------------------------
	p_main : process
		constant C_SCOPE : string := C_TB_SCOPE_DEFAULT;

		type t_seen is array (0 to 2 ** C_WIDTH - 1) of boolean;
		variable v_seen  : t_seen                                  := (others => false);
		variable v_model : std_logic_vector(C_WIDTH - 1 downto 0) := C_SEED;
		variable v_idx   : natural;
		variable v_count : natural := 0;

		-- Enable the LFSR for n rising edges. Called on a falling edge, so the
		-- outputs are sampled half a period after the last update.
		procedure step(n : natural := 1) is
		begin
			enable_i <= '1';
			for i in 1 to n loop
				wait until falling_edge(clk);
			end loop;
			enable_i <= '0';
		end procedure;

		-- Keep the LFSR disabled for n clock periods.
		procedure idle(n : natural) is
		begin
			enable_i <= '0';
			for i in 1 to n loop
				wait until falling_edge(clk);
			end loop;
		end procedure;

	begin

		-- Print the configuration to the log
		report_global_ctrl(VOID);
		report_msg_id_panel(VOID);

		enable_log_msg(ALL_MESSAGES);

		log(ID_LOG_HDR, "Start Simulation of TB for LFSR", C_SCOPE);
		set_alert_stop_limit(ERROR, 5); -- stop early, 1023 failing checks are just noise

		------------------------------------------------------------
		clock_ena <= true; -- to start clock generator
		wait until falling_edge(clk);

		--==================================================================================================
		log(ID_LOG_HDR, "Test 1: power-up seed, no movement while disabled", C_SCOPE);
		check_value(lfsr_o, C_SEED, ERROR, "Seed after power-up", C_SCOPE);
		idle(5);
		check_value(lfsr_o, C_SEED, ERROR, "Seed held while enable_i = 0", C_SCOPE);

		--==================================================================================================
		log(ID_LOG_HDR, "Test 2: full period, " & integer'image(C_PERIOD) & " states, each exactly once", C_SCOPE);
		disable_log_msg(ID_POS_ACK); -- 1000+ passing checks would flood the log, failures still print

		v_seen(to_integer(unsigned(C_SEED))) := true;
		v_count                              := 1;

		for i in 1 to C_PERIOD - 1 loop
			step;
			v_model := next_state(v_model);
			check_value(lfsr_o, v_model, ERROR, "State matches reference model", C_SCOPE);

			v_idx := to_integer(unsigned(lfsr_o));
			check_value(v_idx /= 0, true, ERROR, "State is never all-zero", C_SCOPE);
			check_value(v_seen(v_idx), false, ERROR, "State not visited before", C_SCOPE);
			v_seen(v_idx) := true;
			v_count       := v_count + 1;

			-- Pause in the middle of the sequence: the state must freeze, then resume where it left off
			if i = 500 then
				idle(10);
				check_value(lfsr_o, v_model, ERROR, "State held while enable_i = 0 mid-sequence", C_SCOPE);
			end if;
		end loop;

		-- One more step closes the loop: back to the seed after exactly 2^n - 1 clocks
		step;
		enable_log_msg(ID_POS_ACK);
		check_value(lfsr_o, C_SEED, ERROR, "Sequence wraps back to the seed after 1023 clocks", C_SCOPE);
		check_value(v_count, C_PERIOD, ERROR, "All 1023 non-zero states visited exactly once", C_SCOPE);

		--==================================================================================================
		wait for 2 * C_CLK_PERIOD;
		report_alert_counters(FINAL); -- Report final counters and print conclusion for simulation (Success/Fail)
		log(ID_LOG_HDR, "SIMULATION COMPLETED", C_SCOPE);

		-- Finish the simulation
		std.env.stop;
		wait; -- to stop completely

	end process p_main;
end architecture;
