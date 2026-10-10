library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

library STD;
use std.env.all;

library uvvm_util;
context uvvm_util.uvvm_util_context;

use uvvm_util.uart_bfm_pkg.all;

use std.textio.all;
use std.env.finish;

entity tb_uart_tx_uvvm is
end tb_uart_tx_uvvm;

architecture sim of tb_uart_tx_uvvm is
  constant CLK_PERIOD : time := 10 ns; -- 100 MHz
  constant BIT_TIME   : time := 868 * CLK_PERIOD; -- CLK_FREQ / BAUD_RATE clocks, exactly as the DUT counts it

  signal clk : std_logic := '0';

  signal clock_ena : boolean := false;

  signal start_tx : std_logic := '0';

  signal data_in : std_logic_vector(7 downto 0) := (others => '0');
  signal tx_out  : std_logic;
  signal tx_done : std_logic;

  signal terminate_loop : std_logic := '0';

begin
  -----------------------------------------------------------------------------
  -- Clock Generator
  -----------------------------------------------------------------------------
  clock_generator(clk, clock_ena, CLK_PERIOD, "UART_TX TB clock");

  -----------------------------------------------------------------------------
  -- Instantiate DUT
  -----------------------------------------------------------------------------
  DUT : entity work.uart_tx
    generic map(
      CLK_FREQ  => 100_000_000,
      BAUD_RATE => 115_200,
      STOP_BIT  => 1
    )
    port map
    (
      clk      => clk,
      start_tx => start_tx,
      data_in  => data_in,
      tx_out   => tx_out,
      tx_done  => tx_done
    );

  ------------------------------------------------
  -- PROCESS: p_main
  ------------------------------------------------
  p_main : process
    constant C_SCOPE         : string                        := C_TB_SCOPE_DEFAULT;
    variable uart_bfm_config : t_uart_bfm_config             := C_UART_BFM_CONFIG_DEFAULT;
  begin

    -- uart initializations
    uart_bfm_config.bit_time         := BIT_TIME;
    uart_bfm_config.num_data_bits    := 8;
    uart_bfm_config.idle_state       := '1';
    uart_bfm_config.num_stop_bits    := STOP_BITS_ONE;
    uart_bfm_config.parity           := PARITY_NONE;
    uart_bfm_config.timeout          := 20 * BIT_TIME; -- must exceed one frame (10 bit times); 0 would hang forever on a dead DUT
    uart_bfm_config.timeout_severity := error;

    -- Print the configuration to the log
    report_global_ctrl(VOID);
    report_msg_id_panel(VOID);

    enable_log_msg(ALL_MESSAGES);
    --disable_log_msg(ALL_MESSAGES);
    --enable_log_msg(ID_LOG_HDR);

    log(ID_LOG_HDR, "Start Simulation of TB for UART_TX", C_SCOPE);
    set_alert_stop_limit(ERROR, 0); -- 0 = never stop on ERROR, keep running

    ------------------------------------------------------------
    clock_ena <= true; -- to start clock generator

    --==================================================================================================
    -- Stimulus and checks

    wait for 10 * CLK_PERIOD;

    for i in 0 to 255 loop
      data_in  <= std_logic_vector(to_unsigned(i, 8));
      start_tx <= '1';

      uart_expect(
      data_exp       => std_logic_vector(to_unsigned(i, 8)), -- not data_in: the signal still holds the previous byte until this process suspends
      msg            => "byte",
      rx             => tx_out,
      terminate_loop => terminate_loop,
      config         => uart_bfm_config,
      scope          => C_SCOPE
      );

      wait for CLK_PERIOD;
      start_tx <= '0';
      -- tx_done is high during the stop bit and already high here (uart_expect returns mid-stop-bit),
      -- so wait for it to fall = DUT back in idle
      await_value(tx_done, '0', 0 ns, BIT_TIME, ERROR, "tx_done low after stop bit", C_SCOPE);
    end loop;
    --==================================================================================================
    -- Ending the simulation
    --------------------------------------------------------------------------------------
    wait for 1000 ns; -- to allow some time for completion
    report_alert_counters(FINAL); -- Report final counters and print conclusion for simulation (Success/Fail)
    log(ID_LOG_HDR, "SIMULATION COMPLETED", C_SCOPE);

    -- Finish the simulation
    std.env.stop;
    wait; -- to stop completely

  end process p_main;

end sim;
