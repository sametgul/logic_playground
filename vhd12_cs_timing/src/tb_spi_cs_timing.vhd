----------------------------------------------------------------------------------
-- Engineer:    Samet GUL
-- Email:       asam.gul@gmail.com
-- Github:      https://github.com/sametgul
-- LinkedIn:    www.linkedin.com/in/gul-samet
--
-- Create Date: 09.04.2026
-- Description: Minimal testbench for spi_cs_timing — SPI Mode 2 (CPOL=1, CPHA=0)
--              One transaction, CS_SETUP=3, CS_IDLE=3.
--              Inspect cs_n, sclk, mosi, miso, miso_dat in waveform viewer.
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.all;

entity tb_spi_cs_timing is
end tb_spi_cs_timing;

architecture Behavioral of tb_spi_cs_timing is

  constant CLK_FREQ  : integer := 100_000_000;
  constant SCLK_FREQ : integer := 50_000_000;
  constant DATA_W    : integer := 8;
  constant CLK_PER   : time    := 10 ns;

  constant CS_SETUP : integer := 3;
  constant CS_IDLE  : integer := 3;

  signal clk      : std_logic := '0';
  signal start    : std_logic := '0';
  signal busy     : std_logic;
  signal done     : std_logic;
  signal mosi_dat : std_logic_vector(DATA_W - 1 downto 0) := (others => '0');
  signal miso_dat : std_logic_vector(DATA_W - 1 downto 0);
  signal sclk     : std_logic;
  signal mosi     : std_logic;
  signal miso     : std_logic;
  signal cs_n     : std_logic;

  -- Mode 2 slave model
  signal shreg     : std_logic_vector(DATA_W - 1 downto 0) := (others => '0');
  signal slave_dat : std_logic_vector(DATA_W - 1 downto 0) := (others => '0');

begin

  clk <= not clk after CLK_PER / 2;

  -- Slave: load on CS_n fall, shift out MSB on SCK rising edge
  p_SLV : process (cs_n, sclk) begin
    if    falling_edge(cs_n) then shreg <= slave_dat;
    elsif rising_edge(sclk)  then shreg <= shreg(DATA_W - 2 downto 0) & '0';
    end if;
  end process;
  miso <= shreg(DATA_W - 1) when cs_n = '0' else '1';

  -- Stimulus
  p_STIM : process
  begin
    wait for CLK_PER * 5;

    -- Send 0xA5, expect to receive 0x3C from slave
    slave_dat <= x"3C";
    mosi_dat  <= x"A5";
    wait for CLK_PER;

    start <= '1'; wait for CLK_PER; start <= '0';

    -- Wait for transaction to finish
    wait until rising_edge(done);
    wait until falling_edge(done);
    wait for CLK_PER*5;

    assert FALSE report "SIM DONE" severity failure;
  end process;

  DUT : entity work.spi_cs_timing
    generic map (
      CLK_FREQ       => CLK_FREQ,
      SCLK_FREQ      => SCLK_FREQ,
      DATA_W         => DATA_W,
      CPOL           => '1',
      CPHA           => '0',
      CS_SETUP_TICKS => CS_SETUP,
      CS_IDLE_TICKS  => CS_IDLE)
    port map (
      clk      => clk,
      start    => start,
      busy     => busy,
      done     => done,
      mosi_dat => mosi_dat,
      miso_dat => miso_dat,
      sclk     => sclk,
      mosi     => mosi,
      miso     => miso,
      cs_n     => cs_n);

end Behavioral;
