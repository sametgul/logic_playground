library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity tb_uart_rx is
generic(
    CLK_FREQ  : integer := 100_000_000;
    BAUD_RATE : integer := 115_200
);
end tb_uart_rx;

architecture Behavioral of tb_uart_rx is

    signal clk       :  std_logic := '0';
    signal rx_in     :  std_logic := '1';
    signal data_out  :  std_logic_vector(7 downto 0);
    signal read_done :  std_logic;
    
    constant CLK_PERIOD : time := 10 ns;
    signal BAUD_TICK : integer := CLK_FREQ/BAUD_RATE;
    signal data_in   : std_logic_vector(7 downto 0) := x"AB";

begin
    pSTIMULI: process begin
        wait for BAUD_TICK*CLK_PERIOD*2;
        
        -- start bit
        rx_in <= '0';
        wait for BAUD_TICK*CLK_PERIOD;
        
        -- data
        for i in 0 to 7 loop
            rx_in <= data_in(i);
            wait for BAUD_TICK*CLK_PERIOD;
        end loop;
        
        -- stop bit
        rx_in <= '1';
        wait for BAUD_TICK*CLK_PERIOD;
        
        assert false
        report "sim done"
        severity failure;
    end process;
    
    pCLK: process begin
        clk <= '0';
        wait for CLK_PERIOD/2;
        clk <= '1';
        wait for CLK_PERIOD/2;    
    end process;

    DUT: entity work.uart_rx 
    generic map(
        CLK_FREQ  => CLK_FREQ ,
        BAUD_RATE => BAUD_RATE
    )
    port map(
        clk        => clk      ,
        rx_in      => rx_in    ,
        data_out   => data_out ,
        read_done  => read_done
    );



end Behavioral;
