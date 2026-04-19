----------------------------------------------------------------------------------
-- Engineer:    Samet GUL
-- Email:       asam.gul@gmail.com
-- Github:      https://github.com/sametgul
-- LinkedIn:    www.linkedin.com/in/gul-samet
--
-- Create Date: 19.04.2026
-- Description: Testbench for ltc2986_ctrl
--              Simulates two complete PT1000 measurement cycles.
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;

--------------------------------------------------------------------------------
-- Models the LTC2986 SPI slave and verifies ltc2986_ctrl behaviour.
--
-- Simulated transaction sequence (post-startup):
--   Trans 1  — Write global config          (write, MISO don't-care)
--   Trans 2  — Write RSense channel config  (write, MISO don't-care)
--   Trans 3  — Write RTD channel config     (write, MISO don't-care)
--   Trans 4  — Write convert command        (write, MISO don't-care)
--   Trans 5  — Read status register         (MISO: 0x00 = conversion busy)
--   Trans 6  — Read status register         (MISO: 0x40 = conversion done, bit6=1)
--   Trans 7  — Read 4-byte result register  (MISO: 0x00_006400 = 25.0 degC, no fault)
--   Trans 8  — Write convert command        (second cycle)
--   Trans 9  — Read status register         (MISO: 0x40 = done immediately)
--   Trans 10 — Read 4-byte result register  (MISO: same result, 25.0 degC)
--
-- Expected outputs after each result read:
--   fault_code = 0x00   (no sensor fault)
--   temp_raw   = 0x006400  (25.000 degC: 25 x 1024 = 25600 = 0x006400)
--   temp_valid = '1' for one clock cycle
--
-- Simulation parameters are scaled for fast simulation; see generics below.
-- At these settings one byte transfer = 80 ns, full result read ≈ 560 ns.
--------------------------------------------------------------------------------

entity tb_ltc2986_ctrl is
end tb_ltc2986_ctrl;

architecture Behavioral of tb_ltc2986_ctrl is

  -- ── Simulation parameters ─────────────────────────────────────────────────
  constant CLK_FREQ        : integer := 10_000_000; -- 10 MHz (100 ns period)
  constant SCLK_FREQ       : integer := 1_000_000;  -- 1 MHz SCK  → HALF_PER = 5 cycles
  constant CLK_PERIOD      : time    := 100 ns;
  constant STARTUP_TICKS   : integer := 10;          -- tiny delay (1 µs) instead of 200 ms
  constant CONV_WAIT_TICKS : integer := 10;          -- tiny delay (1 µs) instead of 100 ms

  -- ── DUT ports ─────────────────────────────────────────────────────────────
  signal clk        : std_logic := '0';
  signal temp_valid : std_logic;
  signal fault_code : std_logic_vector(7 downto 0);
  signal temp_raw   : std_logic_vector(23 downto 0);
  signal sclk       : std_logic;
  signal mosi       : std_logic;
  signal miso       : std_logic := '0';
  signal cs_n       : std_logic;

  -- ── Expected result ───────────────────────────────────────────────────────
  -- 25.000 degC encoded as signed Q11.10: 25 * 1024 = 25600 = 0x006400
  constant EXP_FAULT : std_logic_vector(7 downto 0)  := x"00";
  constant EXP_TEMP  : std_logic_vector(23 downto 0) := x"006400";

begin

  clk <= not clk after CLK_PERIOD / 2;

  -- ── Device Under Test ─────────────────────────────────────────────────────
  DUT : entity work.ltc2986_ctrl
    generic map (
      CLK_FREQ        => CLK_FREQ,
      SCLK_FREQ       => SCLK_FREQ,
      CH_RSENSE       => 2,
      CH_RTD          => 4,
      STARTUP_TICKS   => STARTUP_TICKS,
      CONV_WAIT_TICKS => CONV_WAIT_TICKS
    )
    port map (
      clk        => clk,
      temp_valid => temp_valid,
      fault_code => fault_code,
      temp_raw   => temp_raw,
      sclk       => sclk,
      mosi       => mosi,
      miso       => miso,
      cs_n       => cs_n
    );

  -- ── LTC2986 SPI slave model ───────────────────────────────────────────────
  -- Drives MISO after each falling SCK edge so the bit is stable before the
  -- next rising edge (the master's sample point in Mode 0).
  --
  -- Byte layout of every SPI transaction: [instr][addr_hi][addr_lo][data ...]
  -- The 3-byte header occupies SCK cycles 1–24; data bytes start at cycle 25.
  -- MISO is only meaningful to the master during data bytes of READ transactions.
  --
  -- fall_cnt  : falling SCK edges counted within current CS_n assertion
  -- trans_num : CS_n assertion count since simulation start
  p_SLAVE : process
    variable trans_num   : integer := 0;
    variable fall_cnt    : integer := 0;
    variable data_bit    : integer := 0;
    variable byte_in_data: integer := 0;
    variable bit_in_byte : integer := 7;
    variable resp_byte   : std_logic_vector(7 downto 0) := x"00";
  begin
    miso <= '0';

    loop
      -- Wait for start of a new transaction (CS_n assertion)
      wait until falling_edge(cs_n);
      trans_num := trans_num + 1;
      fall_cnt  := 0;
      miso      <= '0';

      -- Process SCK edges until CS_n deasserts
      loop
        wait on sclk, cs_n;
        exit when cs_n = '1';
        next when not falling_edge(sclk);

        fall_cnt := fall_cnt + 1;

        -- Past the 3-byte header (24 SCK cycles)?
        -- After fall_cnt falling edges, MISO will be sampled on the next rising edge.
        -- fall_cnt = 24 → MISO is sampled at rising edge 25 = first data bit (MSB of byte 0).
        if fall_cnt >= 24 then
          data_bit     := fall_cnt - 24;       -- 0 = MSB of first data byte
          byte_in_data := data_bit / 8;
          bit_in_byte  := 7 - (data_bit mod 8);

          -- Choose which byte to drive based on transaction type and byte position
          resp_byte := x"00";  -- default: don't care / zero

          -- ── Read transactions ──────────────────────────────────────────────
          -- Trans 1-4 : write-only (global cfg, rsense cfg, rtd cfg, convert cmd)
          -- MISO is don't-care; resp_byte stays 0x00.

          -- Trans 5 : status poll #1 → busy (bit 6 = 0)
          if trans_num = 5 then
            resp_byte := x"00";

          -- Trans 6 : status poll #2 → conversion done (bit 6 = 1)
          elsif trans_num = 6 then
            resp_byte := x"40";

          -- Trans 7 : result read (cycle 1) — 0x00_006400 = 25.000 degC, no fault
          elsif trans_num = 7 then
            case byte_in_data is
              when 0      => resp_byte := x"00";  -- fault flags (none)
              when 1      => resp_byte := x"00";  -- temp[23:16]
              when 2      => resp_byte := x"64";  -- temp[15:8]  (0x006400 = 25 x 1024)
              when 3      => resp_byte := x"00";  -- temp[7:0]
              when others => resp_byte := x"00";
            end case;

          -- Trans 8 : second convert command (write, MISO don't-care)

          -- Trans 9 : status poll (second cycle) → done immediately
          elsif trans_num = 9 then
            resp_byte := x"40";

          -- Trans 10 : result read (cycle 2) — same 25.000 degC reading
          elsif trans_num = 10 then
            case byte_in_data is
              when 0      => resp_byte := x"00";
              when 1      => resp_byte := x"00";
              when 2      => resp_byte := x"64";
              when 3      => resp_byte := x"00";
              when others => resp_byte := x"00";
            end case;

          end if;

          miso <= resp_byte(bit_in_byte);
        else
          miso <= '0';
        end if;

      end loop;

      miso <= '0';
    end loop;
  end process;

  -- ── Result checker ────────────────────────────────────────────────────────
  -- Asserts on every temp_valid pulse; stops simulation after two readings.
  p_CHECK : process
    variable reading_cnt : integer := 0;
  begin
    loop
      wait until rising_edge(clk) and temp_valid = '1';
      reading_cnt := reading_cnt + 1;

      assert fault_code = EXP_FAULT
        report "FAIL reading " & integer'image(reading_cnt) &
               ": fault_code mismatch (expected 0x00)"
        severity error;

      assert temp_raw = EXP_TEMP
        report "FAIL reading " & integer'image(reading_cnt) &
               ": temp_raw mismatch (expected 0x006400 = 25.000 degC)"
        severity error;

      if fault_code = EXP_FAULT and temp_raw = EXP_TEMP then
        report "PASS reading " & integer'image(reading_cnt) &
               ": fault=0x00  temp=0x006400  (25.000 degC)"
        severity note;
      end if;

      if reading_cnt = 2 then
        report "SIM DONE -- both measurement cycles verified." severity failure;
      end if;
    end loop;
  end process;

end Behavioral;
