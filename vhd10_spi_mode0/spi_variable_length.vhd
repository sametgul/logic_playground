----------------------------------------------------------------------------------
-- Engineer: Samet GUL
--
-- Create Date: 25.04.2026
-- Module Name: spi_master - rtl
-- Description: SPI Mode 0 master with variable-length frame support.
--              Valid bytes are always packed at the MSB side of the frame.
--              Data is shifted MSB first.
--              MOSI changes on falling SCK edge.
--              MISO is sampled on rising SCK edge.
--
-- Generics:
--   CLK_FREQ  : System clock frequency in Hz
--   SCLK_FREQ : Target SPI clock frequency in Hz
--               WARNING: SCLK_FREQ must be <= CLK_FREQ/2
--               Example: CLK_FREQ=12MHz → max SCLK_FREQ=6MHz
--
--   MAX_N     : Maximum frame size in bits
--               WARNING: MAX_N must be a multiple of 8 (byte-aligned)
--               Valid values: 8, 16, 24, 32, 40, 48, 56, 64
--               Invalid example: MAX_N=57 will cause undefined behavior
--
--   VALID_N   : Bit width of i_byte_count port
--               WARNING: Must satisfy 2^VALID_N >= MAX_N/8
--               Example: MAX_N=56 → MAX_N/8=7 → need 2^VALID_N >= 7
--                        → VALID_N=3 since 2^3=8 >= 7
--               Invalid example: MAX_N=56 with VALID_N=2 → 2^2=4 < 7 → wrong
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;

entity spi_master is
    generic (
        CLK_FREQ  : integer := 12_000_000; -- System clock frequency in Hz
        SCLK_FREQ : integer := 1_000_000;  -- Target SPI clock frequency in Hz
        MAX_N     : integer := 56;         -- Maximum frame size in bits, must be multiple of 8
        VALID_N   : integer := 3           -- Bit width of byte count port, must satisfy 2^VALID_N >= MAX_N/8
    );
    port (
        clk : in std_logic;
        rst : in std_logic; -- Active high reset

        -- Controller FSM interface
        i_start      : in  std_logic;
        i_tx_data    : in  std_logic_vector(MAX_N - 1 downto 0);   -- Up to MAX_N/8 bytes, MSB first
        i_byte_count : in  std_logic_vector(VALID_N - 1 downto 0); -- Number of valid bytes (1 to MAX_N/8)
        o_rx_data    : out std_logic_vector(MAX_N - 1 downto 0);   -- Received frame, same alignment
        o_ready      : out std_logic; -- High when idle, ready for new transaction
        o_done       : out std_logic; -- Pulses high for one clock when transaction complete

        -- SPI physical signals
        spi_cs_n : out std_logic;
        spi_sck  : out std_logic;
        spi_mosi : out std_logic;
        spi_miso : in  std_logic
    );
end spi_master;

architecture rtl of spi_master is

    -- Number of system clock cycles per half SCK period
    constant HALF_PERIOD : integer := CLK_FREQ / (SCLK_FREQ * 2);

    type t_state is (sIDLE, sTRANSFER, sDONE);
    signal state : t_state := sIDLE;

    -- Half period timer
    signal timer : integer range 0 to HALF_PERIOD - 1 := 0;

    -- Internal SCK, only driven onto pin during TRANSFER
    signal r_sck : std_logic := '0';

    -- Shift registers
    signal tx_shreg : std_logic_vector(MAX_N - 1 downto 0) := (others => '0');
    signal rx_shreg : std_logic_vector(MAX_N - 1 downto 0) := (others => '0');

    -- Bit counters
    -- total_bits: total number of bits to transfer in this frame
    -- bit_cnt:    number of bits sampled so far (incremented on every rising SCK edge)
    signal total_bits : integer range 0 to MAX_N := 0;
    signal bit_cnt    : integer range 0 to MAX_N := 0;

begin

    -- -------------------------------------------------------------------------
    -- Generic constraint checks
    -- Evaluated at elaboration time, before simulation or synthesis runs
    -- synthesis translate_off
    assert (MAX_N mod 8 = 0)
        report "[spi_master] MAX_N=" & integer'image(MAX_N) &
               " is not a multiple of 8. " &
               "Valid values: 8, 16, 24, 32, 40, 48, 56, 64."
        severity failure;

    assert (2**VALID_N >= MAX_N / 8)
        report "[spi_master] VALID_N=" & integer'image(VALID_N) &
               " is too small for MAX_N=" & integer'image(MAX_N) & ". " &
               "Must satisfy 2^VALID_N >= MAX_N/8."
        severity failure;

    assert (SCLK_FREQ <= CLK_FREQ / 2)
        report "[spi_master] SCLK_FREQ=" & integer'image(SCLK_FREQ) &
               " exceeds CLK_FREQ/2=" & integer'image(CLK_FREQ/2) & ". " &
               "SCLK_FREQ must be <= CLK_FREQ/2."
        severity failure;
    -- synthesis translate_on
    -- -------------------------------------------------------------------------

    -- SCK only active during transfer state, idles low (SPI Mode 0)
    spi_sck <= r_sck when state = sTRANSFER else '0';

    process (clk) begin
        if rising_edge(clk) then
            if rst = '1' then
                state      <= sIDLE;
                o_rx_data  <= (others => '0');
                o_ready    <= '0';
                o_done     <= '0';
                spi_cs_n   <= '1';
                spi_mosi   <= '0';
                r_sck      <= '0';
                timer      <= 0;
                tx_shreg   <= (others => '0');
                rx_shreg   <= (others => '0');
                total_bits <= 0;
                bit_cnt    <= 0;

            else

                -- o_done is a single cycle pulse, default low
                o_done <= '0';

                case state is

                    -- ---------------------------------------------------------
                    when sIDLE =>
                    -- ---------------------------------------------------------
                        o_ready  <= '1';
                        spi_cs_n <= '1';
                        spi_mosi <= '0';
                        r_sck    <= '0';
                        timer    <= 0;
                        bit_cnt  <= 0;

                        if i_start = '1' then
                            -- Drive MSB onto MOSI immediately so it is stable
                            -- well before the first rising SCK edge
                            spi_mosi   <= i_tx_data(MAX_N - 1);
                            -- Pre-shift: MSB already consumed, rest loaded into register
                            tx_shreg   <= i_tx_data(MAX_N - 2 downto 0) & '0';
                            total_bits <= to_integer(unsigned(i_byte_count)) * 8;
                            spi_cs_n   <= '0'; -- assert CS for entire frame
                            o_ready    <= '0';
                            state      <= sTRANSFER;
                        end if;

                    -- ---------------------------------------------------------
                    when sTRANSFER =>
                    -- ---------------------------------------------------------
                        if timer = HALF_PERIOD - 1 then
                            timer <= 0;
                            r_sck <= not r_sck;

                            if r_sck = '0' then
                                -- Rising SCK edge: sample MISO into rx shift register
                                rx_shreg <= rx_shreg(MAX_N - 2 downto 0) & spi_miso;
                                bit_cnt  <= bit_cnt + 1;

                            else
                                -- Falling SCK edge: check if all bits have been sampled
                                if bit_cnt = total_bits then
                                    -- All bits sampled on previous rising edges
                                    -- This falling edge completes the last SCK cycle
                                    state <= sDONE;
                                else
                                    -- Drive next MOSI bit from shift register
                                    spi_mosi <= tx_shreg(MAX_N - 1);
                                    tx_shreg <= tx_shreg(MAX_N - 2 downto 0) & '0';
                                end if;
                            end if;

                        else
                            timer <= timer + 1;
                        end if;

                    -- ---------------------------------------------------------
                    when sDONE =>
                    -- ---------------------------------------------------------
                        spi_cs_n  <= '1';      -- deassert CS
                        o_rx_data <= rx_shreg; -- present received data to controller
                        o_done    <= '1';      -- single cycle pulse to controller
                        state     <= sIDLE;

                end case;
            end if;
        end if;
    end process;

end rtl;