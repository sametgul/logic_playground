library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;

--------------------------------------------------------------------------------
-- Testbench for spi_master (Mode 0) — Full Duplex
--
-- A simple SPI slave model drives MISO independently from MOSI.
-- This verifies that TX and RX paths work simultaneously and correctly.
--
-- Test sequence:
--   Transaction 1: master sends 0xA5, slave sends 0x3C
--   Transaction 2: master sends 0xC3, slave sends 0x55
--
-- Expected results:
--   After transaction 1: miso_dat = 0x3C
--   After transaction 2: miso_dat = 0x55
--
-- Slave model behavior (Mode 0):
--   - Loads slave_tx_data when CS_n goes low
--   - Drives MISO MSB first
--   - Shifts out on falling SCK edge (updates before master samples on rising)
--------------------------------------------------------------------------------

entity tb_spi_mode0 is
end tb_spi_mode0;

architecture Behavioral of tb_spi_mode0 is

  constant CLK_FREQ  : integer := 100_000_000;
  constant SCLK_FREQ : integer := 10_000_000;
  constant DATA_W    : integer := 8;
  constant CLK_PER   : time    := 10 ns;

  signal clk      : std_logic := '0';
  signal start    : std_logic := '0';
  signal busy     : std_logic;
  signal done     : std_logic;
  signal mosi_dat : std_logic_vector(DATA_W-1 downto 0) := (others => '0');
  signal miso_dat : std_logic_vector(DATA_W-1 downto 0);
  signal sclk     : std_logic;
  signal mosi     : std_logic;
  signal miso     : std_logic := '1'; -- idle high
  signal cs_n     : std_logic;

  -- Slave model signals
  signal slave_tx_data  : std_logic_vector(DATA_W-1 downto 0) := (others => '0');
  signal slave_tx_shreg : std_logic_vector(DATA_W-1 downto 0) := (others => '0');

begin

  -- Clock
  p_CLK : process begin
    clk <= '0'; wait for CLK_PER / 2;
    clk <= '1'; wait for CLK_PER / 2;
  end process;

  --------------------------------------------------------------------------------
  -- Simple SPI slave model (Mode 0)
  -- Drives MISO MSB first, updates on falling SCK edge
  -- Loads shift register when CS_n goes low
  --------------------------------------------------------------------------------
  p_SLAVE : process (cs_n, sclk)
  begin
    -- Load shift register on CS_n falling edge
    if falling_edge(cs_n) then
      slave_tx_shreg <= slave_tx_data;

    elsif falling_edge(sclk) then
      -- Shift out MSB first on falling SCK edge
      -- Master samples on rising edge so data is stable before next rising edge
      slave_tx_shreg <= slave_tx_shreg(DATA_W-2 downto 0) & '0';
    end if;
  end process;

  -- Drive MISO from MSB of slave shift register
  miso <= slave_tx_shreg(DATA_W-1) when cs_n = '0' else '1';

  --------------------------------------------------------------------------------
  -- Stimulus
  --------------------------------------------------------------------------------
  p_STIM : process begin
    wait for CLK_PER * 10;

    -- Transaction 1: master sends 0xA5, slave sends 0x3C
    slave_tx_data <= x"3C";
    mosi_dat      <= x"A5";
    wait for CLK_PER; -- let slave_tx_data settle

    start <= '1';
    wait for CLK_PER;
    start <= '0';

    wait until done = '1';
    wait for CLK_PER;

    -- Verify result
    assert miso_dat = x"3C"
      report "FAIL: Transaction 1 expected 0x3C got " & 
             integer'image(to_integer(unsigned(miso_dat)))
      severity error;

    wait for CLK_PER * 10;

    -- Transaction 2: master sends 0xC3, slave sends 0x55
    slave_tx_data <= x"55";
    mosi_dat      <= x"C3";
    wait for CLK_PER;

    start <= '1';
    wait for CLK_PER;
    start <= '0';

    wait until done = '1';
    wait for CLK_PER;

    -- Verify result
    assert miso_dat = x"55"
      report "FAIL: Transaction 2 expected 0x55 got " &
             integer'image(to_integer(unsigned(miso_dat)))
      severity error;

    wait for CLK_PER * 10;

    assert FALSE
      report "SIM DONE  all transactions complete"
      severity failure;
  end process;

  -- DUT
  inst_DUT : entity work.spi_mode0
    generic map(
      CLK_FREQ  => CLK_FREQ,
      SCLK_FREQ => SCLK_FREQ,
      DATA_W    => DATA_W
    )
    port map(
      clk      => clk,
      start    => start,
      busy     => busy,
      done     => done,
      mosi_dat => mosi_dat,
      miso_dat => miso_dat,
      sclk     => sclk,
      mosi     => mosi,
      miso     => miso,
      cs_n     => cs_n
    );

end Behavioral;