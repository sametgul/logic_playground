----------------------------------------------------------------------------------
-- Engineer: Samet GUL
-- 
-- Create Date: 23.07.2026 21:54:47
-- Description: Synchronized UART receiver
-- 
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.all;

entity uart_rx_synched is
  generic (
    CLK_FREQ  : integer := 12_000_000;
    BAUD_RATE : integer := 115_200;
    N         : integer := 3
  );
  port (
    clk       : in std_logic;
    rx_in     : in std_logic;
    data_out  : out std_logic_vector(7 downto 0);
    read_done : out std_logic
  );
end uart_rx_synched;

architecture Behavioral of uart_rx_synched is

  signal sync_out : std_logic;

begin

  inst_SYNC : entity work.synchronizer
    generic map(
      N => N
    )
    port map
    (
      clk      => clk,
      async_in => rx_in,
      sync_out => sync_out
    );

  inst_RX : entity work.uart_rx
    generic map(
      CLK_FREQ  => CLK_FREQ,
      BAUD_RATE => BAUD_RATE
    )
    port map
    (
      clk       => clk,
      rx_in     => sync_out,
      data_out  => data_out,
      read_done => read_done
    );

end Behavioral;
