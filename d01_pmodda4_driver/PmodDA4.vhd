----------------------------------------------------------------------------------
-- Engineer:    Samet GUL
-- Email:       asam.gul@gmail.com
-- Github:      https://github.com/sametgul
-- LinkedIn:    www.linkedin.com/in/gul-samet
--
--
-- Create Date: 06.04.2026 20:20:10
-- Description: PmodDA4 AD5628 Driver
-- 
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.all;

entity PmodDA4 is
  generic (
    CLK_FREQ  : integer                      := 100_000_000; -- system clock frequency (Hz)
    SCLK_FREQ : integer                      := 50_000_000; -- desired SCK frequency   (Hz)
    CHANNEL   : std_logic_vector(3 downto 0) := "0000" -- CHA_A = 0000 ... CHA_H = 0111, ALL_CHA = 1111
  );
  port (
    clk      : in std_logic;
    start    : in std_logic; -- 1-cycle pulse: begin transaction
    busy     : out std_logic; -- high while transaction in progress
    done     : out std_logic; -- 1-cycle pulse: transaction complete
    mosi_dat : in std_logic_vector(31 downto 0); -- data to transmit (MSB first)
    sclk     : out std_logic;
    mosi     : out std_logic;
    miso     : in std_logic;
    cs_n     : out std_logic -- chip select, active-low
  );
end PmodDA4;

architecture Behavioral of PmodDA4 is

  signal start_sig : std_logic := '0';
  signal busy_reg  : std_logic := '0';
  signal done_reg  : std_logic := '0';

begin

  start_sig <= start;
  inst_SPI1 : entity work.spi_all_modes
    generic map(
      CLK_FREQ  => CLK_FREQ,
      SCLK_FREQ => SCLK_FREQ,
      DATA_W    => 32,
      CPOL      => '0',
      CPHA      => '1',
      DELAY     => 1
    )
    port map
    (
      clk      => clk,
      start    => start_sig,
      busy     => busy_reg,
      done     => done_reg,
      mosi_dat => mosi_dat,
      sclk     => sclk,
      mosi     => mosi,
      miso     => open,
      cs_n     => cs_n
    );
end Behavioral;
