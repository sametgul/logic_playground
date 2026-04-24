----------------------------------------------------------------------------------
-- Engineer:    Samet GUL
-- Email:       asam.gul@gmail.com
-- Github:      https://github.com/sametgul
-- LinkedIn:    www.linkedin.com/in/gul-samet
--
-- Create Date: 19.04.2026
-- Description: LTC2986 controller — PT1000 4-wire RTD with 1.5 kΩ sense resistor.
--              No hardware reset or /INTERRUPT pin used; status is polled over SPI.
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;

--------------------------------------------------------------------------------
-- Wraps ltc2986_spi and runs the full measurement cycle autonomously:
--
--   1. Power-on wait  (~200 ms)          LTC2986 internal POR settle time
--   2. Write global config               write 0x40 to 0x00F0 (50 Hz rejection)
--   3. Init sense resistor channel       write 4 bytes to channel CH_RSENSE
--   4. Init RTD channel                  write 4 bytes to channel CH_RTD
--   5. Send convert command              write 0x80|CH_RTD to address 0x0000
--   6. Wait ~100 ms                      conversion takes ~170 ms with 50 Hz filter
--   7. Poll status register              read 1 byte from 0x0000, repeat until
--                                        bit 6 = '1' (conversion complete)
--   8. Read temperature result           read 4 bytes from result register
--   9. Present result, go to step 5
--
-- Outputs:
--   temp_valid  — 1-cycle pulse each time a new temperature word is ready
--   fault_code  — upper 8 bits of the 32-bit result (LTC2986 fault flags)
--   temp_raw    — lower 24 bits; signed Q11.10 (1/1024 °C per LSB)
--                 e.g. 25.000 °C → 0x006400  (25 × 1024 = 25600 = 0x6400)
--
-- Channel assignment:
--   CH_RSENSE (default 2)  — sense resistor 1500.0 Ω, sense type 29
--   CH_RTD    (default 4)  — 4-wire PT1000 Kelvin sense, 250 µA, type 15
--------------------------------------------------------------------------------

entity ltc2986_ctrl is
  generic (
    CLK_FREQ        : integer := 100_000_000; -- system clock (Hz)
    SCLK_FREQ       : integer := 2_000_000;   -- SPI SCK, max 2 MHz
    CH_RSENSE       : natural := 2;           -- sense resistor CH1-CH2, assigned to CH2
    CH_RTD          : natural := 4;           -- 4-wire RTD Kelvin sense CH3-CH4, assigned to CH4
    STARTUP_TICKS   : integer := 20_000_000;  -- sys-clk cycles before first SPI (~200 ms at 100 MHz)
    CONV_WAIT_TICKS : integer := 10_000_000   -- sys-clk cycles to wait after convert (~100 ms at 100 MHz)
  );
  port (
    clk        : in  std_logic;
    -- measurement outputs
    temp_valid : out std_logic;                     -- 1-cycle pulse: new reading ready
    fault_code : out std_logic_vector(7 downto 0);  -- LTC2986 fault byte (0x00 = no fault)
    temp_raw   : out std_logic_vector(23 downto 0); -- temperature, signed Q11.10 (1/1024 °C)
    -- SPI bus to LTC2986
    sclk       : out std_logic;
    mosi       : out std_logic;
    miso       : in  std_logic;
    cs_n       : out std_logic
  );
end ltc2986_ctrl;

architecture Behavioral of ltc2986_ctrl is

  -- ── LTC2986 register constants ─────────────────────────────────────────────
  --
  -- Global configuration register (address 0x00F0)
  --   Bit 6 = 1 → 50/60 Hz rejection enabled (50 Hz mode)
  --   Written as 1-byte payload: 0x40, left-justified → wr_data = 0x40000000
  constant GLOBAL_CFG_ADDR : std_logic_vector(15 downto 0) := x"00F0";
  constant GLOBAL_CFG_DATA : std_logic_vector(31 downto 0) := x"40000000";

  -- Sense-resistor channel assignment register (sensor type 29 = 0b11101)
  --   [31:27] = 11101  sensor type = Sense Resistor (type 29)
  --   [26:0]  = 1500 × 1024 = 1 536 000 = 0x177000  (Q17.10, LSB = 1/1024 Ω)
  --   Packed: (29 << 27) | 0x177000 = 0xE8000000 | 0x177000 = 0xE8177000
  constant RSENSE_CFG : std_logic_vector(31 downto 0) := x"E8177000";

  -- RTD channel assignment register for PT1000 4-wire Kelvin sense (type 15)
  --   [31:27] = 01111  sensor type = RTD 4-wire (type 15)
  --   [26:22] = CH_RSENSE (5-bit sense-resistor channel number)
  --   [21:20] = 10     excitation mode = 4-wire Kelvin sense
  --   [19:16] = 0110   excitation current = 250 µA
  --   [15:0]  = 0
  --   With CH_RSENSE=2: 0x78000000 + 0x800000 + 0x200000 + 0x060000 = 0x78A60000
  constant RTD_CFG : std_logic_vector(31 downto 0) :=
    std_logic_vector(to_unsigned(
      15 * 16#8000000# +           -- [31:27]=01111 (type 15, PT1000 4-wire RTD)
      CH_RSENSE * 16#400000# +     -- [26:22] = CH_RSENSE (each step = 2^22)
      2 * 16#100000# +             -- [21:20]=10 (4-wire Kelvin sense mode)
      6 * 16#10000#,               -- [19:16]=0110 (250 µA excitation current)
    32));

  -- Single-channel convert command: bit7=1 (single-ch), bits[4:0]=channel number
  constant CONV_CMD : std_logic_vector(31 downto 0) :=
    std_logic_vector(to_unsigned((16#80# + CH_RTD) * 16#1000000#, 32));

  -- Register addresses
  constant STATUS_ADDR : std_logic_vector(15 downto 0) := x"0000";
  constant RSENSE_ADDR : std_logic_vector(15 downto 0) :=
    std_logic_vector(to_unsigned(16#0200# + (CH_RSENSE - 1) * 4, 16));
  constant RTD_ADDR    : std_logic_vector(15 downto 0) :=
    std_logic_vector(to_unsigned(16#0200# + (CH_RTD    - 1) * 4, 16));
  constant RESULT_ADDR : std_logic_vector(15 downto 0) :=
    std_logic_vector(to_unsigned(16#0010# + (CH_RTD    - 1) * 4, 16));

  -- ── SPI driver signals ─────────────────────────────────────────────────────
  signal spi_start   : std_logic := '0';
  signal spi_rd_wr_n : std_logic := '0';
  signal spi_addr    : std_logic_vector(15 downto 0) := (others => '0');
  signal spi_n_bytes : natural range 1 to 4 := 1;
  signal spi_wr_data : std_logic_vector(31 downto 0) := (others => '0');
  signal spi_rd_data : std_logic_vector(31 downto 0);
  signal spi_done    : std_logic;
  signal spi_busy    : std_logic;

  -- ── State machine ──────────────────────────────────────────────────────────
  type t_state is (
    STARTUP,        -- wait for LTC2986 power-on-reset to settle
    INIT_GLOBAL,    -- write global config: 50 Hz rejection
    WAIT_GLOBAL,
    INIT_RSENSE,    -- write sense-resistor channel config
    WAIT_RSENSE,
    INIT_RTD,       -- write RTD channel config
    WAIT_RTD,
    SEND_CONV,      -- write convert command to status register
    WAIT_CONV,
    CONV_WAIT,      -- wait ~100 ms for conversion to complete (~170 ms total)
    POLL,           -- read status register (1 byte)
    WAIT_POLL,
    CHECK_STATUS,   -- test bit 6; loop back to POLL if not done
    READ_RESULT,    -- read 4-byte temperature result
    WAIT_RESULT     -- capture result and pulse temp_valid
  );
  signal state : t_state := STARTUP;

  signal startup_cnt   : integer range 0 to STARTUP_TICKS   := 0;
  signal conv_wait_cnt : integer range 0 to CONV_WAIT_TICKS := 0;

begin

  U_SPI : entity work.ltc2986_spi
    generic map (
      CLK_FREQ       => CLK_FREQ,
      SCLK_FREQ      => SCLK_FREQ,
      CS_SETUP_TICKS => (CLK_FREQ / 9_090_909) + 1, -- >= 110 ns
      CS_IDLE_TICKS  => (CLK_FREQ / 9_090_909) + 1
    )
    port map (
      clk     => clk,
      start   => spi_start,
      rd_wr_n => spi_rd_wr_n,
      addr    => spi_addr,
      n_bytes => spi_n_bytes,
      wr_data => spi_wr_data,
      rd_data => spi_rd_data,
      busy    => spi_busy,
      done    => spi_done,
      sclk    => sclk,
      mosi    => mosi,
      miso    => miso,
      cs_n    => cs_n
    );

  p_CTRL : process(clk)
  begin
    if rising_edge(clk) then

      -- Defaults (deasserted every cycle unless explicitly set below)
      spi_start  <= '0';
      temp_valid <= '0';

      case state is

        -- ── STARTUP ───────────────────────────────────────────────────────────
        when STARTUP =>
          if startup_cnt = STARTUP_TICKS - 1 then
            state <= INIT_GLOBAL;
          else
            startup_cnt <= startup_cnt + 1;
          end if;

        -- ── INIT_GLOBAL ───────────────────────────────────────────────────────
        -- Write 0x40 to address 0x00F0: enables 50/60 Hz noise rejection.
        when INIT_GLOBAL =>
          spi_start   <= '1';
          spi_rd_wr_n <= '0';
          spi_addr    <= GLOBAL_CFG_ADDR;
          spi_n_bytes <= 1;
          spi_wr_data <= GLOBAL_CFG_DATA;
          state       <= WAIT_GLOBAL;

        when WAIT_GLOBAL =>
          if spi_done = '1' then
            state <= INIT_RSENSE;
          end if;

        -- ── INIT_RSENSE ───────────────────────────────────────────────────────
        when INIT_RSENSE =>
          spi_start   <= '1';
          spi_rd_wr_n <= '0';
          spi_addr    <= RSENSE_ADDR;
          spi_n_bytes <= 4;
          spi_wr_data <= RSENSE_CFG;
          state       <= WAIT_RSENSE;

        when WAIT_RSENSE =>
          if spi_done = '1' then
            state <= INIT_RTD;
          end if;

        -- ── INIT_RTD ──────────────────────────────────────────────────────────
        when INIT_RTD =>
          spi_start   <= '1';
          spi_rd_wr_n <= '0';
          spi_addr    <= RTD_ADDR;
          spi_n_bytes <= 4;
          spi_wr_data <= RTD_CFG;
          state       <= WAIT_RTD;

        when WAIT_RTD =>
          if spi_done = '1' then
            state <= SEND_CONV;
          end if;

        -- ── SEND_CONV ─────────────────────────────────────────────────────────
        when SEND_CONV =>
          spi_start   <= '1';
          spi_rd_wr_n <= '0';
          spi_addr    <= STATUS_ADDR;
          spi_n_bytes <= 1;
          spi_wr_data <= CONV_CMD;
          state       <= WAIT_CONV;

        when WAIT_CONV =>
          if spi_done = '1' then
            conv_wait_cnt <= 0;
            state         <= CONV_WAIT;
          end if;

        -- ── CONV_WAIT ─────────────────────────────────────────────────────────
        -- LTC2986 needs ~170 ms to complete one conversion in 50 Hz mode.
        -- Waiting CONV_WAIT_TICKS (~100 ms) before the first poll avoids
        -- hammering the bus with unnecessary status reads.
        when CONV_WAIT =>
          if conv_wait_cnt = CONV_WAIT_TICKS - 1 then
            state <= POLL;
          else
            conv_wait_cnt <= conv_wait_cnt + 1;
          end if;

        -- ── POLL ──────────────────────────────────────────────────────────────
        -- Read 1 byte from status register; bit 6 = 1 when conversion is done.
        when POLL =>
          spi_start   <= '1';
          spi_rd_wr_n <= '1';
          spi_addr    <= STATUS_ADDR;
          spi_n_bytes <= 1;
          state       <= WAIT_POLL;

        when WAIT_POLL =>
          if spi_done = '1' then
            state <= CHECK_STATUS;
          end if;

        -- ── CHECK_STATUS ──────────────────────────────────────────────────────
        -- spi_rd_data[31:24] = status byte (left-justified, 1-byte read)
        -- Bit 6 of the status byte = bit 30 of spi_rd_data
        when CHECK_STATUS =>
          if spi_rd_data(30) = '1' then -- bit 6 of status byte = conversion done
            state <= READ_RESULT;
          else
            state <= POLL;              -- not done yet; poll again
          end if;

        -- ── READ_RESULT ───────────────────────────────────────────────────────
        when READ_RESULT =>
          spi_start   <= '1';
          spi_rd_wr_n <= '1';
          spi_addr    <= RESULT_ADDR;
          spi_n_bytes <= 4;
          state       <= WAIT_RESULT;

        -- ── WAIT_RESULT ───────────────────────────────────────────────────────
        -- spi_rd_data[31:24] = fault flags, spi_rd_data[23:0] = temperature
        when WAIT_RESULT =>
          if spi_done = '1' then
            fault_code <= spi_rd_data(31 downto 24);
            temp_raw   <= spi_rd_data(23 downto 0);
            temp_valid <= '1';
            state      <= SEND_CONV;   -- immediately queue next conversion
          end if;

      end case;
    end if;
  end process;

end Behavioral;
