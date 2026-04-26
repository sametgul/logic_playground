--------------------------------------------------------------------------------
-- Testbench for spi_master — variable-length frame (Mode 0)
--
-- A simple SPI slave model drives MISO independently from MOSI.
-- This verifies TX, RX, and reset behavior across different frame lengths.
--
-- Test sequence:
--   TEST 1: Master sends AB CD EF         (3 bytes), slave sends A1 B2 C3
--   TEST 2: Master sends AA BB CC DD EE FF 99 (7 bytes), slave sends 11 22 33 44 55 66 77
--   TEST 3: Start a 4-byte transfer, assert rst mid-transfer, verify recovery
--
-- Expected results:
--   TEST 1: o_rx_data = 00 00 00 00 A1 B2 C3  (received bytes in lower bytes)
--   TEST 2: o_rx_data = 11 22 33 44 55 66 77
--   TEST 3: spi_cs_n = '1', o_ready = '1' after reset
--
-- Slave model behavior (Mode 0):
--   - Loads slave_tx_data when CS_n goes low
--   - Drives MISO MSB first
--   - Shifts out on falling SCK edge (updates before master samples on rising)
--
-- RX alignment: received bytes land in the LOWER bytes of o_rx_data.
--   e.g. 3-byte transfer: o_rx_data[55:24] = 0, o_rx_data[23:0] = received bytes
--------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;

entity tb_spi_variable_frame is
  generic (
    CLK_FREQ  : integer := 12_000_000;
    SCLK_FREQ : integer := 1_000_000;
    MAX_N     : integer := 56;
    VALID_N   : integer := 3
  );
end tb_spi_variable_frame;

architecture Behavioral of tb_spi_variable_frame is

  -- HALF_PER = sys-clk cycles per half SCK period (6 for 12 MHz / 1 MHz)
  constant CLK_PERIOD : time    := 1_000_000_000 ns / CLK_FREQ;
  constant HALF_PER   : integer := CLK_FREQ / (SCLK_FREQ * 2);

  signal clk : std_logic := '0';
  signal rst : std_logic := '0';

  signal i_start      : std_logic                              := '0';
  signal i_tx_data    : std_logic_vector(MAX_N - 1 downto 0)   := (others => '0');
  signal i_byte_count : std_logic_vector(VALID_N - 1 downto 0) := (others => '0');
  signal o_rx_data    : std_logic_vector(MAX_N - 1 downto 0);
  signal o_ready      : std_logic;
  signal o_done       : std_logic;

  signal spi_cs_n : std_logic;
  signal spi_sck  : std_logic;
  signal spi_mosi : std_logic;
  signal spi_miso : std_logic := '0';

  -- Slave model: set slave_tx_data before each transaction
  signal slave_tx_data  : std_logic_vector(MAX_N - 1 downto 0) := (others => '0');
  signal slave_tx_shreg : std_logic_vector(MAX_N - 1 downto 0) := (others => '0');

begin

  -- Clock
  p_CLK : process begin
    clk <= '0';
    wait for CLK_PERIOD / 2;
    clk <= '1';
    wait for CLK_PERIOD / 2;
  end process;

  --------------------------------------------------------------------------------
  -- Simple SPI slave model (Mode 0)
  -- Loads shift register when CS_n goes low
  -- Drives MISO MSB first, shifts on falling SCK edge
  --------------------------------------------------------------------------------
  p_SLAVE : process (spi_cs_n, spi_sck) begin
    if falling_edge(spi_cs_n) then
      slave_tx_shreg <= slave_tx_data;
    elsif falling_edge(spi_sck) then
      slave_tx_shreg <= slave_tx_shreg(MAX_N - 2 downto 0) & '0';
    end if;
  end process;

  spi_miso <= slave_tx_shreg(MAX_N - 1) when spi_cs_n = '0' else
    '0';

  --------------------------------------------------------------------------------
  -- Stimulus
  --------------------------------------------------------------------------------
  p_STIM : process begin
    wait for CLK_PERIOD * 5;

    -- TEST 1: Master sends AB CD EF, slave sends A1 B2 C3 (top 3 bytes)
    -- Expected o_rx_data: 00 00 00 00 A1 B2 C3
    slave_tx_data <= x"A1_B2_C3_00_00_00_00";
    i_tx_data     <= x"AB_CD_EF_00_00_00_00";
    i_byte_count  <= "011";
    wait for CLK_PERIOD;
    i_start <= '1';
    wait for CLK_PERIOD;
    i_start <= '0';
    wait until o_done = '1';
    wait for CLK_PERIOD;
    assert o_rx_data = x"00_00_00_00_A1_B2_C3"
    report "TEST 1 FAIL: unexpected o_rx_data" severity error;

    wait for CLK_PERIOD * 5;

    -- TEST 2: Master sends AA BB CC DD EE FF 99, slave sends 11 22 33 44 55 66 77
    -- Expected o_rx_data: 11 22 33 44 55 66 77
    slave_tx_data <= x"11_22_33_44_55_66_77";
    i_tx_data     <= x"AA_BB_CC_DD_EE_FF_99";
    i_byte_count  <= "111";
    wait for CLK_PERIOD;
    i_start <= '1';
    wait for CLK_PERIOD;
    i_start <= '0';
    wait until o_done = '1';
    wait for CLK_PERIOD;
    assert o_rx_data = x"11_22_33_44_55_66_77"
    report "TEST 2 FAIL: unexpected o_rx_data" severity error;

    wait for CLK_PERIOD * 5;

    -- TEST 3: Reset mid-transaction
    -- Start a 4-byte transfer, assert rst after ~4 SCK cycles, verify recovery
    slave_tx_data <= (others => '0');
    i_tx_data     <= x"CA_FE_BA_BE_00_00_00";
    i_byte_count  <= "100";
    wait for CLK_PERIOD;
    i_start <= '1';
    wait for CLK_PERIOD;
    i_start <= '0';

    wait for CLK_PERIOD * (HALF_PER * 2 * 4 + 2); -- ~4 SCK cycles into transfer
    rst <= '1';
    wait for CLK_PERIOD * 2;
    rst <= '0';
    wait for CLK_PERIOD * 3;

    assert spi_cs_n = '1'
    report "TEST 3 FAIL: CS_N not deasserted after reset" severity error;
    assert o_ready = '1'
    report "TEST 3 FAIL: o_ready not high after reset" severity error;

    wait for CLK_PERIOD * 5;
    assert FALSE
    report "SIM DONE  all tests complete"
      severity failure;
  end process;

  --------------------------------------------------------------------------------
  -- DUT
  --------------------------------------------------------------------------------
  inst_DUT : entity work.spi_master
    generic map(
      CLK_FREQ  => CLK_FREQ,
      SCLK_FREQ => SCLK_FREQ,
      MAX_N     => MAX_N,
      VALID_N   => VALID_N
    )
    port map
    (
      clk          => clk,
      rst          => rst,
      i_start      => i_start,
      i_tx_data    => i_tx_data,
      i_byte_count => i_byte_count,
      o_rx_data    => o_rx_data,
      o_ready      => o_ready,
      o_done       => o_done,
      spi_cs_n     => spi_cs_n,
      spi_sck      => spi_sck,
      spi_mosi     => spi_mosi,
      spi_miso     => spi_miso
    );

end Behavioral;
