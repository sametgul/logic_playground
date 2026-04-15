----------------------------------------------------------------------------------
-- Engineer:    Samet GUL
-- Email:       asam.gul@gmail.com
-- Github:      https://github.com/sametgul
-- LinkedIn:    www.linkedin.com/in/gul-samet
--
-- Create Date: 14.04.2026
-- Description: Top-level for sawtooth wave generation on Cmod A7.
--              12 MHz on-board oscillator → clk_wiz_0 → 100 MHz system clock.
--              sawtooth_gen drives PmodDA4 continuously on CH_A.
--              All logic runs on clk100 to avoid CDC violations.
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.all;

entity top_sawtooth is
  generic (
    CLK_FREQ  : integer := 100_000_000;
    SCLK_FREQ : integer := 50_000_000
  );
  port (
    clk  : in std_logic; -- 12 MHz on-board oscillator
    sclk : out std_logic;
    mosi : out std_logic;
    cs_n : out std_logic
  );
end top_sawtooth;

architecture Behavioral of top_sawtooth is

  signal start   : std_logic := '0';
  signal done    : std_logic;
  signal busy    : std_logic;
  signal clk100  : std_logic;
  signal dac_val : std_logic_vector(11 downto 0) := (others => '0');

begin

  inst_STG : entity work.sawtooth_gen
    port map(
      clk     => clk100,
      busy    => busy,
      dac_val => dac_val,
      start   => start
    );

  inst_DA4 : entity work.PmodDA4
    generic map(
      CLK_FREQ  => CLK_FREQ,
      SCLK_FREQ => SCLK_FREQ
    )
    port map(
      clk      => clk100,
      start    => start,
      da4_done => done,
      busy     => busy,
      CHANNEL  => "0000", -- CH_A
      dac_val  => dac_val,
      sclk     => sclk,
      mosi     => mosi,
      cs_n     => cs_n
    );

  inst_CW : entity work.clk_wiz_0
    port map(
      clk_out1 => clk100,
      clk_in1  => clk
    );

end Behavioral;
