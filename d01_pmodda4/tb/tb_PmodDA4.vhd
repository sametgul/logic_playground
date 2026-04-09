----------------------------------------------------------------------------------
-- Engineer:    Samet GUL
-- Description: Self-checking testbench for PmodDA4 (AD5628 driver)
--
-- SPI Mode 2 (CPOL=1, CPHA=0): SCLK idles HIGH, master samples MOSI on
-- falling SCLK edge. Slave model captures MOSI on every falling SCLK edge.
--
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;

entity tb_PmodDA4 is
end tb_PmodDA4;

architecture Behavioral of tb_PmodDA4 is

  constant CLK_FREQ  : integer := 100_000_000;
  constant SCLK_FREQ : integer := 25_000_000;
  constant CLK_PER   : time    := 10 ns;

  signal clk     : std_logic                     := '0';
  signal start   : std_logic                     := '0';
  signal done    : std_logic                     := '0';
  signal CHANNEL : std_logic_vector(3 downto 0)  := "0000";
  signal dac_val : std_logic_vector(11 downto 0) := (others => '0');

  signal sclk : std_logic;
  signal mosi : std_logic;
  signal cs_n : std_logic;

  -- Slave MOSI capture (Mode 2: sample on falling SCLK)
  signal slave_rx_shreg : std_logic_vector(31 downto 0) := (others => '0');

begin

  -- 100 MHz clock
  clk <= not clk after CLK_PER / 2;

  -- DUT
  inst_DA4 : entity work.PmodDA4
    generic map(
      CLK_FREQ  => CLK_FREQ,
      SCLK_FREQ => SCLK_FREQ
    )
    port map
    (
      clk      => clk,
      start    => start,
      da4_done => done,
      CHANNEL  => CHANNEL,
      dac_val  => dac_val,
      sclk     => sclk,
      mosi     => mosi,
      cs_n     => cs_n
    );

  -- SPI Mode 2 slave: reset on cs_n falling, capture MOSI on SCLK falling edge
  p_SLAVE : process (cs_n, sclk)
  begin
    if falling_edge(cs_n) then
      slave_rx_shreg <= (others => '0');
    elsif falling_edge(sclk) then
      slave_rx_shreg <= slave_rx_shreg(30 downto 0) & mosi;
    end if;
  end process;

  -- Stimulus
  p_STIM : process
  begin
    wait for CLK_PER * 5;

    -- Test 1: CH_A (0000), dac_val = 0xABC 
    CHANNEL <= "0000";
    dac_val <= x"ABC";
    wait for CLK_PER;

    start <= '1';
    wait for CLK_PER;
    start <= '0';
    wait until done = '1';
    wait for CLK_PER; -- let slave_rx_shreg settle

    assert slave_rx_shreg = x"030ABC00"
      report "FAIL Test 1: expected 0x030ABC00"
      severity error;

    -- Test 2: CH_B (0001), dac_val = 0x7FF
    CHANNEL <= "0001";
    dac_val <= x"7FF";
    wait for CLK_PER;

    start <= '1';
    wait for CLK_PER;
    start <= '0';
    wait until done = '1';
    wait for CLK_PER; -- let slave_rx_shreg settle

    assert slave_rx_shreg = x"0317FF00"
      report "FAIL Test 2: expected 0x0317FF00"
      severity error;

    wait for CLK_PER * 5;

    assert FALSE report "SIM COMPLETE -- all tests passed" severity failure;
  end process;

end Behavioral;