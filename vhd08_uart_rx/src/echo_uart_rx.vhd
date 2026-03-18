library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity echo_uart_rx is
generic(
    CLK_FREQ  : integer := 12_000_000;
    BAUD_RATE : integer := 115_200;
    STOP_BIT  : integer := 1
);
port(
    clk     : in  std_logic;
    uart_rx : in  std_logic;
    uart_tx : out std_logic;
    led     : out std_logic_vector(1 downto 0)
);
end echo_uart_rx;

architecture Behavioral of echo_uart_rx is

    signal rx_data      : std_logic_vector(7 downto 0);
    signal received1    : std_logic_vector(7 downto 0);
    signal received2    : std_logic_vector(7 downto 0);
    signal received3    : std_logic_vector(7 downto 0);
    signal rx_done      : std_logic;
    signal r_led        : std_logic_vector(1 downto 0) := "01";

    signal start_tx     : std_logic := '0';
    signal datain       : std_logic_vector(7 downto 0) := (others => '0');
    signal tx_done      : std_logic;
    signal tx_done_prev : std_logic := '0';

    type t_state is (STATE1, STATE2, STATE3, STATE4, STATE5, STATE6);
    signal state : t_state := STATE1;

begin

    led <= r_led;

    pUART_RX: process(clk)
    begin
        if rising_edge(clk) then

            -- Defaults: clear start_tx each cycle unless explicitly set
            -- Prevents uart_tx from retriggering on IDLE re-entry
            start_tx     <= '0';
            tx_done_prev <= tx_done;

            case state is

                -- Receiving phase: wait for 3-byte sequence 0xA1 → 0xB2 → 0xC3
                when STATE1 =>
                    if (rx_done = '1') then
                        if (rx_data = x"A1") then
                            received1 <= rx_data;
                            state     <= STATE2;
                        end if;
                    end if;

                when STATE2 =>
                    if (rx_done = '1') then
                        if (rx_data = x"B2") then
                            received2 <= rx_data;
                            state     <= STATE3;
                        end if;
                    end if;

                when STATE3 =>
                    if (rx_done = '1') then
                        if (rx_data = x"C3") then
                            received3 <= rx_data;
                            state     <= STATE4;
                        end if;
                    end if;

                -- Sending phase: echo back the 3 received bytes
                when STATE4 =>
                    -- Send first byte — pre-assign datain alongside start_tx
                    -- so uart_tx latches the correct data on the same cycle
                    start_tx <= '1';
                    datain   <= received1;
                    state    <= STATE5;

                when STATE5 =>
                    -- Wait for first transmission to complete, then send second byte
                    if (tx_done_prev = '1' and tx_done = '0') then
                        start_tx <= '1';
                        datain   <= received2;
                        state    <= STATE6;
                    end if;

                when STATE6 =>
                    -- Wait for second transmission to complete, then send third byte
                    if (tx_done_prev = '1' and tx_done = '0') then
                        start_tx <= '1';
                        datain   <= received3;
                        state    <= STATE1;
                        r_led    <= not r_led; -- sending done
                    end if;

            end case;
        end if;
    end process;

    inst_RX: entity work.uart_rx
    generic map(
        CLK_FREQ  => CLK_FREQ,
        BAUD_RATE => BAUD_RATE
    )
    port map(
        clk       => clk,
        rx_in     => uart_rx,
        data_out  => rx_data,
        read_done => rx_done
    );

    inst_TX: entity work.uart_tx
    generic map(
        CLK_FREQ  => CLK_FREQ,
        BAUD_RATE => BAUD_RATE,
        STOP_BIT  => STOP_BIT
    )
    port map(
        clk      => clk,
        start_tx => start_tx,
        data_in  => datain,
        tx_out   => uart_tx,
        tx_done  => tx_done
    );

end Behavioral;