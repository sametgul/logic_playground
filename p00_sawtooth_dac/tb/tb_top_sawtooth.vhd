library IEEE;
use IEEE.STD_LOGIC_1164.all;

entity tb_top_sawtooth is
end tb_top_sawtooth;

architecture Behavioral of tb_top_sawtooth is

  signal clk  : std_logic := '0'; -- 12 MHz on-board oscillator
  signal sclk : std_logic;
  signal mosi : std_logic;
  signal cs_n : std_logic;

  constant CLK_PERIOD : time := 83.3 ns;

begin

  pCLK_GEN : process begin
    clk <= '0';
    wait for CLK_PERIOD/2;
    clk <= '1';
    wait for CLK_PERIOD/2;
  end process;

  DUT : entity work.top_sawtooth
    generic map(
      CLK_FREQ  => 100_000_000,
      SCLK_FREQ => 50_000_000
    )
    port map
    (
      clk  => clk,
      sclk => sclk,
      mosi => mosi,
      cs_n => cs_n
    );
end Behavioral;
