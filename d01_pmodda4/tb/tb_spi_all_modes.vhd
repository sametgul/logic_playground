library IEEE;
use IEEE.STD_LOGIC_1164.all;

--------------------------------------------------------------------------------
-- Testbench: spi_all_modes -- All 4 SPI Modes, Full Duplex
--
-- Four DUT instances run in parallel, one per mode, driven by a shared
-- start pulse and shared mosi_dat. Each has its own behavioral slave model.
--
-- Slave model behavior per mode:
--   CPOL=0 (Modes 0,1): slave shifts MISO on falling SCK edge
--   CPOL=1 (Modes 2,3): slave shifts MISO on rising  SCK edge
--   All modes load the shift register on the falling edge of CS_n.
--
-- Test sequence (two transactions):
--   Transaction 1: master sends 0xA5, slave sends 0x3C -> expect miso_dat = 0x3C
--   Transaction 2: master sends 0xC3, slave sends 0x55 -> expect miso_dat = 0x55
--
-- Results are checked with assert statements after each transaction.
-- "SIM PASS" is reported at the end via severity failure to stop simulation.
--------------------------------------------------------------------------------

entity tb_spi_all_modes is
end tb_spi_all_modes;

architecture Behavioral of tb_spi_all_modes is

  constant CLK_FREQ  : integer := 100_000_000;
  constant SCLK_FREQ : integer :=  25_000_000;
  constant DATA_W    : integer := 8;
  constant CLK_PER   : time    := 10 ns;

  signal clk   : std_logic := '0';
  signal start : std_logic := '0';

  -- DUT done/busy
  signal done0, done1, done2, done3 : std_logic;
  signal busy0, busy1, busy2, busy3 : std_logic;

  -- Shared TX data, separate RX per mode
  signal mosi_dat  : std_logic_vector(DATA_W - 1 downto 0) := (others => '0');
  signal miso_dat0 : std_logic_vector(DATA_W - 1 downto 0);
  signal miso_dat1 : std_logic_vector(DATA_W - 1 downto 0);
  signal miso_dat2 : std_logic_vector(DATA_W - 1 downto 0);
  signal miso_dat3 : std_logic_vector(DATA_W - 1 downto 0);

  -- SPI buses
  signal sclk0, mosi0, miso0, cs_n0 : std_logic;
  signal sclk1, mosi1, miso1, cs_n1 : std_logic;
  signal sclk2, mosi2, miso2, cs_n2 : std_logic;
  signal sclk3, mosi3, miso3, cs_n3 : std_logic;

  -- Slave shift registers
  signal slave_tx_data   : std_logic_vector(DATA_W - 1 downto 0) := (others => '0');
  signal slave_tx_shreg0 : std_logic_vector(DATA_W - 1 downto 0) := (others => '0');
  signal slave_tx_shreg1 : std_logic_vector(DATA_W - 1 downto 0) := (others => '0');
  signal slave_tx_shreg2 : std_logic_vector(DATA_W - 1 downto 0) := (others => '0');
  signal slave_tx_shreg3 : std_logic_vector(DATA_W - 1 downto 0) := (others => '0');

begin

  -- Clock
  p_CLK : process begin
    clk <= '0'; wait for CLK_PER / 2;
    clk <= '1'; wait for CLK_PER / 2;
  end process;

  -- Slave: Mode 0 (CPOL=0, CPHA=0) -- SCK idles LOW, shift on falling SCK
  p_SLAVE0 : process (cs_n0, sclk0) begin
    if    falling_edge(cs_n0) then slave_tx_shreg0 <= slave_tx_data;
    elsif falling_edge(sclk0) then slave_tx_shreg0 <= slave_tx_shreg0(DATA_W - 2 downto 0) & '0';
    end if;
  end process;
  miso0 <= slave_tx_shreg0(DATA_W - 1) when cs_n0 = '0' else '1';

  -- Slave: Mode 1 (CPOL=0, CPHA=1) -- SCK idles LOW, shift on falling SCK
  p_SLAVE1 : process (cs_n1, sclk1) begin
    if    falling_edge(cs_n1) then slave_tx_shreg1 <= slave_tx_data;
    elsif falling_edge(sclk1) then slave_tx_shreg1 <= slave_tx_shreg1(DATA_W - 2 downto 0) & '0';
    end if;
  end process;
  miso1 <= slave_tx_shreg1(DATA_W - 1) when cs_n1 = '0' else '1';

  -- Slave: Mode 2 (CPOL=1, CPHA=0) -- SCK idles HIGH, shift on rising SCK
  p_SLAVE2 : process (cs_n2, sclk2) begin
    if    falling_edge(cs_n2) then slave_tx_shreg2 <= slave_tx_data;
    elsif rising_edge(sclk2)  then slave_tx_shreg2 <= slave_tx_shreg2(DATA_W - 2 downto 0) & '0';
    end if;
  end process;
  miso2 <= slave_tx_shreg2(DATA_W - 1) when cs_n2 = '0' else '1';

  -- Slave: Mode 3 (CPOL=1, CPHA=1) -- SCK idles HIGH, shift on rising SCK
  p_SLAVE3 : process (cs_n3, sclk3) begin
    if    falling_edge(cs_n3) then slave_tx_shreg3 <= slave_tx_data;
    elsif rising_edge(sclk3)  then slave_tx_shreg3 <= slave_tx_shreg3(DATA_W - 2 downto 0) & '0';
    end if;
  end process;
  miso3 <= slave_tx_shreg3(DATA_W - 1) when cs_n3 = '0' else '1';

  -- Stimulus and assertions
  p_STIM : process begin
    wait for CLK_PER * 10;

    -- Transaction 1: master -> 0xA5, slave -> 0x3C
    slave_tx_data <= x"3C";
    mosi_dat      <= x"A5";
    wait for CLK_PER;

    start <= '1'; wait for CLK_PER;
    start <= '0';

    wait until (done0 = '1' and done1 = '1' and done2 = '1' and done3 = '1');
    wait for CLK_PER;

    assert miso_dat0 = x"3C" report "TXN1 MODE0 FAIL: expected 0x3C" severity error;
    assert miso_dat1 = x"3C" report "TXN1 MODE1 FAIL: expected 0x3C" severity error;
    assert miso_dat2 = x"3C" report "TXN1 MODE2 FAIL: expected 0x3C" severity error;
    assert miso_dat3 = x"3C" report "TXN1 MODE3 FAIL: expected 0x3C" severity error;

    wait for CLK_PER * 10;

    -- Transaction 2: master -> 0xC3, slave -> 0x55
    slave_tx_data <= x"55";
    mosi_dat      <= x"C3";
    wait for CLK_PER;

    start <= '1'; wait for CLK_PER;
    start <= '0';

    wait until (done0 = '1' and done1 = '1' and done2 = '1' and done3 = '1');
    wait for CLK_PER;

    assert miso_dat0 = x"55" report "TXN2 MODE0 FAIL: expected 0x55" severity error;
    assert miso_dat1 = x"55" report "TXN2 MODE1 FAIL: expected 0x55" severity error;
    assert miso_dat2 = x"55" report "TXN2 MODE2 FAIL: expected 0x55" severity error;
    assert miso_dat3 = x"55" report "TXN2 MODE3 FAIL: expected 0x55" severity error;

    wait for CLK_PER * 10;

    assert FALSE report "SIM PASS -- all transactions complete" severity failure;
  end process;

  -- DUT instantiations
  inst_MODE0 : entity work.spi_all_modes
    generic map (CLK_FREQ => CLK_FREQ, SCLK_FREQ => SCLK_FREQ, DATA_W => DATA_W, CPOL => '0', CPHA => '0')
    port map (clk => clk, start => start, busy => busy0, done => done0,
              mosi_dat => mosi_dat, miso_dat => miso_dat0,
              sclk => sclk0, mosi => mosi0, miso => miso0, cs_n => cs_n0);

  inst_MODE1 : entity work.spi_all_modes
    generic map (CLK_FREQ => CLK_FREQ, SCLK_FREQ => SCLK_FREQ, DATA_W => DATA_W, CPOL => '0', CPHA => '1')
    port map (clk => clk, start => start, busy => busy1, done => done1,
              mosi_dat => mosi_dat, miso_dat => miso_dat1,
              sclk => sclk1, mosi => mosi1, miso => miso1, cs_n => cs_n1);

  inst_MODE2 : entity work.spi_all_modes
    generic map (CLK_FREQ => CLK_FREQ, SCLK_FREQ => SCLK_FREQ, DATA_W => DATA_W, CPOL => '1', CPHA => '0')
    port map (clk => clk, start => start, busy => busy2, done => done2,
              mosi_dat => mosi_dat, miso_dat => miso_dat2,
              sclk => sclk2, mosi => mosi2, miso => miso2, cs_n => cs_n2);

  inst_MODE3 : entity work.spi_all_modes
    generic map (CLK_FREQ => CLK_FREQ, SCLK_FREQ => SCLK_FREQ, DATA_W => DATA_W, CPOL => '1', CPHA => '1')
    port map (clk => clk, start => start, busy => busy3, done => done3,
              mosi_dat => mosi_dat, miso_dat => miso_dat3,
              sclk => sclk3, mosi => mosi3, miso => miso3, cs_n => cs_n3);

end Behavioral;
