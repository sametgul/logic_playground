library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity top_uart_tx_btn is
generic(
    CLK_FREQ  : integer := 12_000_000;
    BAUD_RATE : integer := 115_200;
    STOP_BIT  : integer := 1
);
port(
    sysclk          : in std_logic;
    btn             : in std_logic;
    led             : out std_logic;
    uart_rxd_out    : out std_logic
);
end top_uart_tx_btn;

architecture Behavioral of top_uart_tx_btn is
    signal st      : std_logic := '0';
    signal cnt     : unsigned(7 downto 0) := (others => '0');
    signal datain  : std_logic_vector(7 downto 0) := (others => '0');

    signal btn_prev : std_logic := '0';

    type t_state is (IDLE, DATA, sWAIT);
    signal state : t_state := IDLE;

    signal tx_done_prev : std_logic := '0';
    signal tx_done_r : std_logic := '0';

begin
    process(sysclk) begin
    if rising_edge(sysclk) then
        btn_prev <= btn;
        tx_done_prev <= tx_done_r;

        case state is
            when IDLE =>
                cnt <= (others => '0');  -- reset here so it's always clean
                -- Edge detection: fires once on rising edge of debounced button
                if (btn = '1' and btn_prev = '0') then
                    state <= DATA;
                end if;

            when DATA =>
                cnt    <= cnt + 1;
                -- cnt + 1 expression evaluated immediately (not a signal read)
                -- ensures datain is valid on the same cycle st goes high
                datain <= std_logic_vector(cnt + 1);
                st     <= '1';
                state  <= sWAIT;

            when sWAIT =>
                st <= '0';
                -- tx_done falling edge: uart_tx has finished stop bits and returned to IDLE
                if (tx_done_prev = '1' and tx_done_r = '0') then
                    if (cnt = 3) then
                        state <= IDLE;
                    else
                        state <= DATA;
                    end if;
                end if;
        end case;
    end if;
    end process;

    led <= tx_done_r;

      -- DUT
    inst_uart: entity work.uart_tx
    generic map(
      CLK_FREQ  => CLK_FREQ,
      BAUD_RATE => BAUD_RATE,
      STOP_BIT  => STOP_BIT
    )
    port map(
      clk      => sysclk,
      start_tx => st,
      data_in  => datain,
      tx_out   => uart_rxd_out,
      tx_done  => tx_done_r
    );


end Behavioral;
