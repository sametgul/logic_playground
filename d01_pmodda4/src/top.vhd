----------------------------------------------------------------------------------
-- Engineer:    Samet GUL
-- Description: Top-level wrapper for PmodDA4 on Cmod A7
--              12 MHz sysclk, SCLK = 3 MHz (HALF_PER = 2)
--              BTN0 → triggers one SPI transaction
--              LED  → toggles on each completed transaction
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.all;

entity top is
  port (
    clk  : in  std_logic;  -- 12 MHz on-board oscillator
    btn  : in  std_logic;  -- BTN0, active high
    led  : out std_logic;  -- toggles each completed transaction
    sclk : out std_logic;
    mosi : out std_logic;
    cs_n : out std_logic
  );
end top;

architecture Behavioral of top is

  constant CLK_F  : integer := 12_000_000;
  constant SCLK_F : integer :=  3_000_000;

  signal btn_sync : std_logic_vector(1 downto 0) := "00";
  signal btn_prev : std_logic                    := '0';
  signal start    : std_logic                    := '0';
  signal done     : std_logic;
  signal led_r    : std_logic                    := '0';

begin

  led <= led_r;

  p_CTRL : process (clk)
  begin
    if rising_edge(clk) then
      -- 2-FF synchronizer + rising-edge detect → 1-cycle start pulse
      btn_sync <= btn_sync(0) & btn;
      btn_prev <= btn_sync(1);
      start    <= btn_sync(1) and not btn_prev;

      -- Toggle LED so the 1-cycle done pulse is visible
      if done = '1' then
        led_r <= not led_r;
      end if;
    end if;
  end process;

  inst_DA4 : entity work.PmodDA4
    generic map(
      CLK_FREQ  => CLK_F,
      SCLK_FREQ => SCLK_F
    )
    port map(
      clk      => clk,
      start    => start,
      da4_done => done,
      CHANNEL  => "0000",  -- CH_A
      dac_val  => x"ABC",  -- fixed test value ≈ 1.65 V with internal ref
      sclk     => sclk,
      mosi     => mosi,
      cs_n     => cs_n
    );

end Behavioral;
