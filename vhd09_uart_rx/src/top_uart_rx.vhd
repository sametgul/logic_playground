library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity top_uart_rx is
generic(
    CLK_FREQ  : integer := 12_000_000;
    BAUD_RATE : integer := 115_200
);
port(
    clk         : in  std_logic;
    uart_txd_in : in  std_logic;
    led         : out std_logic_vector(1 downto 0)
);
end top_uart_rx;

architecture Behavioral of top_uart_rx is

    signal uart_data : std_logic_vector(7 downto 0);
    signal rx_done   : std_logic;
    signal r_led     : std_logic_vector(1 downto 0) := "01";

    type t_state is (STATE1, STATE2, STATE3);
    signal state : t_state := STATE1;
begin
    
    led <= r_led;
    process(clk) 
    begin
        if rising_edge(clk) then
            case state is 
                when STATE1 =>
                    if(rx_done = '1') then
                        if(uart_data = x"A1") then
                            state <= STATE2;
                        end if;
                    end if;
                when STATE2 =>
                    if(rx_done = '1') then
                            if(uart_data = x"B2") then
                                state <= STATE3;
                            end if;
                    end if;
                when STATE3 =>
                    if(rx_done = '1') then
                            if(uart_data = x"c3") then
                                state <= STATE3;
                                r_led <= not r_led;
                            end if;
                    end if;
            end case;
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
        read_done => rx_done
    );

end Behavioral;
