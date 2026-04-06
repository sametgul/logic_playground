library IEEE;
use IEEE.STD_LOGIC_1164.all;

--------------------------------------------------------------------------------
-- SPI Master — All 4 Modes (CPOL/CPHA configurable)
--
-- SPI Mode Summary (Motorola convention):
--   Mode 0: CPOL=0, CPHA=0  SCK idles LOW,  sample rising,  shift falling
--   Mode 1: CPOL=0, CPHA=1  SCK idles LOW,  shift rising,   sample falling
--   Mode 2: CPOL=1, CPHA=0  SCK idles HIGH, sample falling, shift rising
--   Mode 3: CPOL=1, CPHA=1  SCK idles HIGH, shift falling,  sample rising
--
-- Edge detection (zero extra latency):
--   Edges are inferred from the timer and the CURRENT value of sclk_r.
--   Because sclk_r <= not sclk_r is a registered assignment, sclk_r still
--   holds its OLD value in the same cycle the timer expires:
--     sclk_r = CPOL     → "first  edge": SCK is about to leave  idle
--     sclk_r = not CPOL → "second edge": SCK is about to return to idle
--
-- CPHA=0: sample MISO on first edge, shift MOSI on second edge.
--   MSB is pre-loaded onto MOSI before CS_n asserts (one full HALF_PER
--   of setup time before the first SCK edge).
--
-- CPHA=1: shift MOSI on first edge, sample MISO on second edge.
--   tx_shreg is loaded with the full mosi_dat word at transaction start;
--   the first bit is driven on the first SCK edge.
--
-- SCK is not free-running — the timer resets on every transaction start,
-- so SCK phase is always deterministic regardless of when start fires.
--------------------------------------------------------------------------------

entity spi_all_modes is
  generic (
    CLK_FREQ  : integer   := 12_000_000; -- system clock frequency (Hz)
    SCLK_FREQ : integer   := 1_000_000; -- desired SCK frequency   (Hz)
    DATA_W    : integer   := 8; -- transaction width in bits
    CPOL      : std_logic := '0'; -- '0' = SCK idles low,  '1' = idles high
    CPHA      : std_logic := '0'; -- '0' = sample-first,   '1' = shift-first
    DELAY_LIM : integer   := 0 -- Delay between CS low and first SCLK edge
  );
  port (
    clk      : in std_logic;
    start    : in std_logic; -- 1-cycle pulse: begin transaction
    busy     : out std_logic; -- high while transaction in progress
    done     : out std_logic; -- 1-cycle pulse: transaction complete
    mosi_dat : in std_logic_vector(DATA_W - 1 downto 0); -- data to transmit (MSB first)
    miso_dat : out std_logic_vector(DATA_W - 1 downto 0); -- data received    (MSB first)
    sclk     : out std_logic;
    mosi     : out std_logic;
    miso     : in std_logic;
    cs_n     : out std_logic -- chip select, active-low
  );
end spi_all_modes;

architecture Behavioral of spi_all_modes is

  -- Number of system-clock cycles per SCK half-period
  constant HALF_PER : integer := CLK_FREQ / (SCLK_FREQ * 2);

  type t_state is (IDLE, TRANSFER, DONE_ST);
  signal state : t_state := IDLE;

  signal timer  : integer range 0 to HALF_PER - 1 := 0;
  signal sclk_r : std_logic                       := CPOL;

  signal tx_shreg : std_logic_vector(DATA_W - 1 downto 0) := (others => '0');
  signal rx_shreg : std_logic_vector(DATA_W - 1 downto 0) := (others => '0');
  signal bit_cnt  : integer range 0 to DATA_W - 1         := 0;

begin

  -- SCK only toggles during TRANSFER; idles at CPOL at all other times
  sclk <= sclk_r when state = TRANSFER else
    CPOL;

  p_MAIN : process (clk)
  begin
    if rising_edge(clk) then

      done <= '0'; -- default; held high for exactly one cycle in DONE_ST

      case state is

          -- ── IDLE ────────────────────────────────────────────────────────────
        when IDLE =>
          busy    <= '0';
          cs_n    <= '1';
          mosi    <= '0';
          bit_cnt <= 0;

          if start = '1' then
            cs_n   <= '0';
            busy   <= '1';
            timer  <= 0;
            sclk_r <= CPOL; -- ensure SCK always starts from its idle level

            if CPHA = '0' then
              -- Pre-load MSB so MOSI is valid before the first SCK edge
              mosi     <= mosi_dat(DATA_W - 1);
              tx_shreg <= mosi_dat(DATA_W - 2 downto 0) & '0';
            else
              -- CPHA=1: first bit is driven ON the first SCK edge, not before
              tx_shreg <= mosi_dat; -- FIX: load full word for CPHA=1
            end if;

            state <= TRANSFER;
          end if;

          -- ── TRANSFER ────────────────────────────────────────────────────────
        when TRANSFER =>
          busy <= '1';

          if timer = HALF_PER - 1 then
            timer  <= 0;
            sclk_r <= not sclk_r; -- toggle SCK (registered; old value still readable below)

            if sclk_r = CPOL then
              -- ── First edge: SCK leaving idle ──────────────────────────────
              --   CPHA=0 → SAMPLE edge: capture MISO
              --   CPHA=1 → SHIFT  edge: drive next MOSI bit

              if CPHA = '0' then
                rx_shreg <= rx_shreg(DATA_W - 2 downto 0) & miso;
              else
                mosi     <= tx_shreg(DATA_W - 1);
                tx_shreg <= tx_shreg(DATA_W - 2 downto 0) & '0';
              end if;

            else
              -- ── Second edge: SCK returning to idle ────────────────────────
              --   CPHA=0 → SHIFT  edge: drive next MOSI bit
              --   CPHA=1 → SAMPLE edge: capture MISO

              -- FIX: sample MISO before checking done so the last bit is
              -- always captured even when transitioning to DONE_ST
              if CPHA = '1' then
                rx_shreg <= rx_shreg(DATA_W - 2 downto 0) & miso;
              end if;

              if bit_cnt = DATA_W - 1 then
                state <= DONE_ST; -- all bits transferred
              else
                if CPHA = '0' then
                  mosi     <= tx_shreg(DATA_W - 1);
                  tx_shreg <= tx_shreg(DATA_W - 2 downto 0) & '0';
                end if;
                bit_cnt <= bit_cnt + 1; -- FIX: increment for both CPHA values
              end if;

            end if;

          else
            timer <= timer + 1;
          end if;

          -- ── DONE ────────────────────────────────────────────────────────────
        when DONE_ST =>
          miso_dat <= rx_shreg;
          done     <= '1';
          busy     <= '0';
          cs_n     <= '1';
          mosi     <= '0';
          state    <= IDLE;

      end case;
    end if;
  end process;

end Behavioral;
