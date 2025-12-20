library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity top is
generic(
    CLK_FREQ  : integer := 12_000_000;
    BAUD_RATE : integer := 115_200
);
port(
    clk         : in  std_logic;
    uart_txd_in : in  std_logic;
    led         : out std_logic_vector(1 downto 0)
);
end top;

architecture Behavioral of top is

    signal uart_data : std_logic_vector(7 downto 0);
    signal rx_tick   : std_logic;
    signal r_led     : std_logic_vector(1 downto 0);
begin
    
    led <= r_led;
    process(clk) begin
    if rising_edge(clk) then
        if(rx_tick = '1') then
           r_led <=  uart_data(1 downto 0);
        end if;
    end if;
    end process;
    
    

    RX_inst: entity work.uart_rx
    generic map(
        CLK_FREQ  => CLK_FREQ ,
        BAUD_RATE => BAUD_RATE
    )
    port map(
        clk       => clk,
        rx_in     => uart_txd_in,
        data_out  => uart_data,
        read_done => rx_tick
    );

end Behavioral;
