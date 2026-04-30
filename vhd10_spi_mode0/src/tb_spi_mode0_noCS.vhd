library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;

--------------------------------------------------------------------------------
-- Testbench for spi_master (Mode 0, no CS) — Full Duplex
--
-- CS is driven here in the stimulus process to prove the clean boundary:
-- spi_master has no knowledge of CS; the caller owns it.
--
-- Test sequence:
--   Transaction 1: master sends 0xA5, slave sends 0x3C
--   Transaction 2: master sends 0xC3, slave sends 0x55
--
-- Expected:
--   After transaction 1: rx_data = 0x3C
--   After transaction 2: rx_data = 0x55
--
-- Slave model (Mode 0):
--   Loads shift register when CS_n goes low
--   Drives MISO MSB-first, updates on falling SCK edge
--------------------------------------------------------------------------------

entity tb_spi_master is
end tb_spi_master;

architecture Behavioral of tb_spi_master is

  constant CLK_FREQ  : integer := 100_000_000;
  constant SCLK_FREQ : integer := 10_000_000;
  constant N_BITS    : integer := 8;
  constant CLK_PER   : time    := 10 ns;

  signal clk     : std_logic := '0';
  signal start   : std_logic := '0';
  signal busy    : std_logic;
  signal done    : std_logic;
  signal tx_data : std_logic_vector(N_BITS-1 downto 0) := (others => '0');
  signal rx_data : std_logic_vector(N_BITS-1 downto 0);
  signal sclk    : std_logic;
  signal mosi    : std_logic;
  signal miso    : std_logic := '1';

  -- CS driven by stimulus — spi_master does not own this
  signal cs_n    : std_logic := '1';

  -- Slave model signals
  signal slave_tx_data  : std_logic_vector(N_BITS-1 downto 0) := (others => '0');
  signal slave_tx_shreg : std_logic_vector(N_BITS-1 downto 0) := (others => '0');

begin

  p_CLK : process begin
    clk <= '0'; wait for CLK_PER / 2;
    clk <= '1'; wait for CLK_PER / 2;
  end process;

  --------------------------------------------------------------------------------
  -- Simple SPI slave model (Mode 0)
  -- Loads shift register on CS_n falling edge
  -- Drives MISO MSB-first, shifts on falling SCK
  --------------------------------------------------------------------------------
  p_SLAVE : process (cs_n, sclk)
  begin
    if falling_edge(cs_n) then
      slave_tx_shreg <= slave_tx_data;
    elsif falling_edge(sclk) then
      slave_tx_shreg <= slave_tx_shreg(N_BITS-2 downto 0) & '0';
    end if;
  end process;

  miso <= slave_tx_shreg(N_BITS-1) when cs_n = '0' else '1';

  --------------------------------------------------------------------------------
  -- Stimulus
  -- CS is asserted here — demonstrating that the caller controls it,
  -- not spi_master
  --------------------------------------------------------------------------------
  p_STIM : process begin
    wait for CLK_PER * 10;

    -- Transaction 1: master sends 0xA5, slave sends 0x3C
    slave_tx_data <= x"3C";
    tx_data       <= x"A5";
    wait for CLK_PER;

    cs_n  <= '0';          -- assert CS before start pulse
    start <= '1';
    wait for CLK_PER;
    start <= '0';

    wait until done = '1';
    wait for CLK_PER;
    cs_n <= '1';           -- deassert CS after done

    assert rx_data = x"3C"
      report "FAIL: Transaction 1 expected 0x3C got " &
             integer'image(to_integer(unsigned(rx_data)))
      severity error;

    wait for CLK_PER * 10;

    -- Transaction 2: master sends 0xC3, slave sends 0x55
    slave_tx_data <= x"55";
    tx_data       <= x"C3";
    wait for CLK_PER;

    cs_n  <= '0';
    start <= '1';
    wait for CLK_PER;
    start <= '0';

    wait until done = '1';
    wait for CLK_PER;
    cs_n <= '1';

    assert rx_data = x"55"
      report "FAIL: Transaction 2 expected 0x55 got " &
             integer'image(to_integer(unsigned(rx_data)))
      severity error;

    wait for CLK_PER * 10;

    assert FALSE
      report "SIM DONE  all transactions complete"
      severity failure;
  end process;

  inst_DUT : entity work.spi_mode0_nocs
    generic map(
      CLK_FREQ  => CLK_FREQ,
      SCLK_FREQ => SCLK_FREQ,
      N_BITS    => N_BITS
    )
    port map(
      clk     => clk,
      start   => start,
      busy    => busy,
      done    => done,
      tx_data => tx_data,
      rx_data => rx_data,
      sclk    => sclk,
      mosi    => mosi,
      miso    => miso
    );

end Behavioral;
