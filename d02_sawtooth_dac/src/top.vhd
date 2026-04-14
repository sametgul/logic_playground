----------------------------------------------------------------------------------
-- Engineer:    Samet GUL
-- Create Date: 14.04.2026
-- Description: Top-level for d02_sawtooth_dac
--              Sawtooth wave generator driving PmodDA4 (AD5628) via SPI Mode 2
--
--              Clock chain: 12 MHz (crystal) → clk_wiz_0 (MMCM) → 100 MHz
--              SPI:         SCLK = 50 MHz, CS timing meets AD5628 t4 / t8
--              Waveform:    Sawtooth on CH_A, frequency set by SAW_FREQ generic
--
-- NOTE: Add Clocking Wizard IP in Vivado before building:
--       IP Catalog → Clocking Wizard → name it "clk_wiz_0"
--       Input clock: 12 MHz  |  Output clock: 100 MHz
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.all;

entity top is
  port (
    clk  : in  std_logic;   -- 12 MHz on-board oscillator (Cmod A7)
    led  : out std_logic;   -- toggles on each completed DAC write
    cs_n : out std_logic;
    mosi : out std_logic;
    sclk : out std_logic
  );
end top;

architecture Behavioral of top is

  signal clk100   : std_logic;
  signal locked   : std_logic;

  signal dac_val  : std_logic_vector(11 downto 0);
  signal busy     : std_logic;
  signal start    : std_logic;
  signal da4_done : std_logic;

  signal led_r    : std_logic := '0';

begin

  led <= led_r;

  -- Toggle LED on each completed DAC write (visible heartbeat)
  p_LED : process (clk100) begin
    if rising_edge(clk100) then
      if da4_done = '1' then
        led_r <= not led_r;
      end if;
    end if;
  end process;

  -- 12 MHz → 100 MHz
  -- Create in Vivado: IP Catalog → Clocking Wizard → clk_wiz_0
  --   Primary input:  12 MHz
  --   Output clk_out1: 100 MHz
  inst_CLK : entity work.clk_wiz_0
    port map(
      clk_in1  => clk,
      clk_out1 => clk100,
      locked   => locked    -- high when PLL is stable; tie to reset if needed
    );

  inst_SAW : entity work.sawtooth_gen
    generic map(
      CLK_FREQ => 100_000_000,
      SAW_FREQ => 100          -- 100 Hz sawtooth; change here to tune frequency
    )
    port map(
      clk     => clk100,
      busy    => busy,
      dac_val => dac_val,
      start   => start
    );

  inst_DA4 : entity work.PmodDA4
    generic map(
      CLK_FREQ  => 100_000_000,
      SCLK_FREQ =>  50_000_000
    )
    port map(
      clk      => clk100,
      start    => start,
      busy     => busy,
      da4_done => da4_done,
      CHANNEL  => "0000",   -- CH_A
      dac_val  => dac_val,
      sclk     => sclk,
      mosi     => mosi,
      cs_n     => cs_n
    );

end Behavioral;
