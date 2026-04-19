----------------------------------------------------------------------------------
-- Engineer:    Samet GUL
-- Email:       asam.gul@gmail.com
-- Github:      https://github.com/sametgul
-- LinkedIn:    www.linkedin.com/in/gul-samet
--
-- Create Date: 19.04.2026
-- Description: SPI Master for LTC2986/LTC2986-1 Temperature Measurement IC
--              SPI Mode 0 (CPOL=0, CPHA=0), configurable CS timing
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.all;

--------------------------------------------------------------------------------
-- Low-level SPI master for the LTC2986/LTC2986-1 temperature measurement IC.
-- Handles raw byte-level transfers only; use ltc2986_ctrl for the full
-- initialization + polling + result-reading sequence.
--
-- Protocol: SPI Mode 0 (CPOL=0, CPHA=0), MSB-first, SCK <= 2 MHz.
--
-- Transaction structure (3-byte header + 1-4 data bytes, CS held low throughout):
--   Write: CS_n low  [0x02][addr_hi][addr_lo][byte0 .. byteN-1]  CS_n high
--   Read : CS_n low  [0x03][addr_hi][addr_lo]  then N bytes in   CS_n high
--
-- Data word convention -- left-justified (MSB first in the 32-bit port):
--   wr_data[31:24]  first byte transmitted
--   rd_data[31:24]  first byte received from the device
--   For n_bytes=1:  wr_data[31:24] = the byte to send;  rd_data[31:24] = received
--   For n_bytes=4:  wr_data[31:0]  = full 32-bit value; rd_data[31:0]  = full result
--   Unused lower bytes of wr_data are don't-cares.
--   Unused lower bytes of rd_data are 0x00 after completion.
--
-- Timing at 100 MHz system clock with the default generics:
--   HALF_PER       = 25 cycles = 250 ns  (2 MHz SCK, 250 ns min half-period spec)
--   CS_SETUP_TICKS = 11 cycles = 110 ns  (>= 100 ns t_CSS spec)
--   CS_IDLE_TICKS  = 11 cycles = 110 ns  (inter-frame CS_n deassert time)
--------------------------------------------------------------------------------

entity ltc2986_spi is
  generic (
    CLK_FREQ       : integer := 100_000_000; -- system clock frequency (Hz)
    SCLK_FREQ      : integer := 2_000_000;   -- SCK frequency, max 2 MHz for LTC2986
    CS_SETUP_TICKS : integer := 11;          -- sys-clk cycles CS_n low before first SCK edge
    CS_IDLE_TICKS  : integer := 11           -- sys-clk cycles CS_n must stay high between frames
  );
  port (
    clk       : in  std_logic;
    -- user interface
    start     : in  std_logic;                     -- 1-cycle pulse: begin transaction
    rd_wr_n   : in  std_logic;                     -- '1'=read (0x03), '0'=write (0x02)
    addr      : in  std_logic_vector(15 downto 0); -- LTC2986 register address
    n_bytes   : in  natural range 1 to 4;          -- number of data bytes to transfer
    wr_data   : in  std_logic_vector(31 downto 0); -- TX data, left-justified MSB first
    rd_data   : out std_logic_vector(31 downto 0); -- RX data, left-justified MSB first
    busy      : out std_logic;                     -- high while transaction is in progress
    done      : out std_logic;                     -- 1-cycle pulse when transaction complete
    -- SPI pins
    sclk      : out std_logic;
    mosi      : out std_logic;
    miso      : in  std_logic;
    cs_n      : out std_logic
  );
end ltc2986_spi;

architecture Behavioral of ltc2986_spi is

  -- SCK half-period in sys-clk cycles
  constant HALF_PER : integer := CLK_FREQ / (SCLK_FREQ * 2);

  type t_state is (IDLE, CS_SETUP, SEND_BYTE, DONE_ST, CS_IDLE);
  signal state : t_state := IDLE;

  -- Pre-built packet: [instr][addr_hi][addr_lo][data_byte_0..3]
  type t_packet is array(0 to 6) of std_logic_vector(7 downto 0);
  signal pkt : t_packet;

  signal timer       : integer range 0 to HALF_PER + CS_SETUP_TICKS + CS_IDLE_TICKS := 0;
  signal sclk_r      : std_logic := '0';
  signal tx_shreg    : std_logic_vector(7 downto 0) := (others => '0');
  signal rx_shreg    : std_logic_vector(7 downto 0) := (others => '0');
  signal bit_cnt     : integer range 0 to 7 := 0;
  signal byte_cnt    : integer range 0 to 6 := 0;
  signal total_bytes : integer range 4 to 7 := 4;
  signal rd_buf      : std_logic_vector(31 downto 0) := (others => '0');

begin

  -- SCK only active during SEND_BYTE; idles low (Mode 0)
  sclk <= sclk_r when state = SEND_BYTE else '0';

  p_MAIN : process(clk)
  begin
    if rising_edge(clk) then

      done <= '0'; -- default; asserted for exactly one cycle in DONE_ST

      case state is

        -- ── IDLE ──────────────────────────────────────────────────────────────
        when IDLE =>
          busy     <= '0';
          cs_n     <= '1';
          mosi     <= '0';
          bit_cnt  <= 0;
          byte_cnt <= 0;

          if start = '1' then
            -- Build 7-byte packet; registered, available from next cycle onward
            pkt(0)      <= "000000" & '1' & rd_wr_n; -- 0x03=read, 0x02=write
            pkt(1)      <= addr(15 downto 8);
            pkt(2)      <= addr(7 downto 0);
            pkt(3)      <= wr_data(31 downto 24);     -- first data byte
            pkt(4)      <= wr_data(23 downto 16);
            pkt(5)      <= wr_data(15 downto 8);
            pkt(6)      <= wr_data(7 downto 0);       -- fourth data byte
            total_bytes <= 3 + n_bytes;
            rd_buf      <= (others => '0');
            cs_n        <= '0';
            busy        <= '1';
            timer       <= 0;
            state       <= CS_SETUP;
          end if;

        -- ── CS_SETUP ──────────────────────────────────────────────────────────
        -- Hold CS_n low for CS_SETUP_TICKS before the first SCK edge (t_CSS).
        -- On exit, MOSI is pre-driven with the MSB of the instruction byte so
        -- it is stable for >= HALF_PER cycles before the first rising SCK edge.
        when CS_SETUP =>
          if timer = CS_SETUP_TICKS - 1 then
            -- pkt(0) is now registered and valid; pre-drive MSB
            sclk_r   <= '0';
            mosi     <= pkt(0)(7);
            tx_shreg <= pkt(0)(6 downto 0) & '0';
            timer    <= 0;
            state    <= SEND_BYTE;
          else
            timer <= timer + 1;
          end if;

        -- ── SEND_BYTE ─────────────────────────────────────────────────────────
        -- Shifts bytes out of pkt[] one byte at a time, MSB first.
        --
        -- Edge strategy (zero extra latency, same as spi_mode0.vhd):
        --   sclk_r holds its OLD value when timer fires:
        --     sclk_r='0' (about to go high) → rising  edge → sample MISO
        --     sclk_r='1' (about to go low)  → falling edge → update MOSI
        when SEND_BYTE =>
          busy <= '1';

          if timer = HALF_PER - 1 then
            timer  <= 0;
            sclk_r <= not sclk_r;

            if sclk_r = '0' then
              -- ── Rising edge: sample MISO (Mode 0 sample edge) ───────────────
              rx_shreg <= rx_shreg(6 downto 0) & miso;

            else
              -- ── Falling edge: shift MOSI or end byte ────────────────────────
              if bit_cnt < 7 then
                -- Mid-byte: drive next MOSI bit
                mosi     <= tx_shreg(7);
                tx_shreg <= tx_shreg(6 downto 0) & '0';
                bit_cnt  <= bit_cnt + 1;

              else
                -- Last falling edge of this byte (bit_cnt=7).
                -- rx_shreg holds all 8 received bits at this point.

                -- Capture received byte into rd_buf (data bytes only: byte_cnt >= 3)
                if    byte_cnt = 3 then rd_buf(31 downto 24) <= rx_shreg;
                elsif byte_cnt = 4 then rd_buf(23 downto 16) <= rx_shreg;
                elsif byte_cnt = 5 then rd_buf(15 downto 8)  <= rx_shreg;
                elsif byte_cnt = 6 then rd_buf(7  downto 0)  <= rx_shreg;
                end if;

                if byte_cnt = total_bytes - 1 then
                  -- All bytes done
                  state <= DONE_ST;
                else
                  -- Load next byte; pre-drive its MSB so MOSI is valid before
                  -- the next rising edge (HALF_PER cycles away)
                  mosi     <= pkt(byte_cnt + 1)(7);
                  tx_shreg <= pkt(byte_cnt + 1)(6 downto 0) & '0';
                  bit_cnt  <= 0;
                  byte_cnt <= byte_cnt + 1;
                end if;
              end if;
            end if;

          else
            timer <= timer + 1;
          end if;

        -- ── DONE_ST ───────────────────────────────────────────────────────────
        when DONE_ST =>
          rd_data <= rd_buf;
          done    <= '1';
          busy    <= '0';
          cs_n    <= '1';
          mosi    <= '0';

          if CS_IDLE_TICKS = 0 then
            state <= IDLE;
          else
            timer <= 0;
            state <= CS_IDLE;
          end if;

        -- ── CS_IDLE ───────────────────────────────────────────────────────────
        -- Enforce minimum CS_n high time between frames.
        when CS_IDLE =>
          if timer = CS_IDLE_TICKS - 1 then
            state <= IDLE;
          else
            timer <= timer + 1;
          end if;

      end case;
    end if;
  end process;

end Behavioral;
