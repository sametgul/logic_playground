-- This module is written for CMOD A7-35T board
-- It instantiates N debouncers, each connected to a button and an LED
-- Buttons are active high by default (can be changed with ACTIVE_LOW generic)

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity top is
generic(
    CLK_FREQ   : integer := 12_000_000;    -- Hz
    DEBTIME_MS : integer := 10;             -- ms   
    ACTIVE_LOW : boolean := false;    
    N          : integer := 2
);
port(
    clk : in std_logic;
    btn  : in std_logic_vector(N-1 downto 0);
    led : out std_logic_vector(N-1 downto 0)
);
end top;

architecture Behavioral of top is
  signal btn_s0, btn_s1 : std_logic_vector(N-1 downto 0) := (others=>'0');
begin
  -- Add a 2-FF synchronizer for button inputs
  -- to avoid metastability issues
  pSYNC: process(clk) begin
    if rising_edge(clk) then
      btn_s0 <= btn;
      btn_s1 <= btn_s0;
    end if;
  end process;

  -- generate debouncers
  N_DEB_GEN: for i in 0 to N-1 generate
    DEB_inst: entity work.debouncer
      generic map(
        CLK_FREQ   => CLK_FREQ,
        DEBTIME_MS => DEBTIME_MS,
        ACTIVE_LOW => ACTIVE_LOW
      )
      port map(
        clk     => clk,
        sig_in  => btn_s1(i),   -- use synchronized button
        sig_out => led(i)
      );
  end generate;
end Behavioral;
