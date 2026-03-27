library IEEE;
use IEEE.STD_LOGIC_1164.all;

--------------------------------------------------------------------------------
-- SPI Master — Mode 0 (CPOL=0, CPHA=0)
--
-- Mode 0 timing:
--   SCK idle low
--   MOSI is pre-loaded before the first rising SCK edge
--   MISO is sampled on rising SCK edge
--   MOSI updates on falling SCK edge
--
-- Edge detection strategy:
--   Instead of comparing registered SCK values (which adds 1-2 cycles of
--   latency), edges are detected directly from the timer:
--     timer = HALF_PER-1 AND sclk_r = '0' → rising edge is about to occur
--     timer = HALF_PER-1 AND sclk_r = '1' → falling edge is about to occur
--   Acting on these conditions in the same cycle as the SCK toggle gives
--   minimum latency — MISO is sampled and MOSI updated exactly on the edge.
--
-- SCK is not free-running — timer resets on transaction start so SCK phase
-- is always deterministic regardless of when start is asserted.
--------------------------------------------------------------------------------

entity spi_master is
  generic (
    CLK_FREQ  : integer := 12_000_000; -- Hz
    SCLK_FREQ : integer := 1_000_000;  -- Hz
    DATA_W    : integer := 8           -- transaction width in bits
  );
  port (
    clk      : in  std_logic;
    start    : in  std_logic;          -- 1-cycle pulse to begin transaction
    busy     : out std_logic;          -- high while transaction in progress
    done     : out std_logic;          -- 1-cycle pulse when complete
    mosi_dat : in  std_logic_vector(DATA_W-1 downto 0);
    miso_dat : out std_logic_vector(DATA_W-1 downto 0);
    sclk     : out std_logic;
    mosi     : out std_logic;
    miso     : in  std_logic;
    cs_n     : out std_logic
  );
end spi_master;

architecture Behavioral of spi_master is

  constant HALF_PER : integer := CLK_FREQ / (SCLK_FREQ * 2);

  type t_state is (IDLE, TRANSFER, DONE_ST);
  signal state : t_state := IDLE;

  signal timer    : integer range 0 to HALF_PER - 1 := 0;
  signal sclk_r   : std_logic := '0';

  signal tx_shreg : std_logic_vector(DATA_W-1 downto 0) := (others => '0');
  signal rx_shreg : std_logic_vector(DATA_W-1 downto 0) := (others => '0');
  signal bit_cnt  : integer range 0 to DATA_W-1         := 0;

begin

  -- SCK output: only active during TRANSFER, idle low (Mode 0)
  sclk <= sclk_r when state = TRANSFER else '0';

  p_MAIN : process (clk)
  begin
    if rising_edge(clk) then

      done <= '0'; -- default

      case state is

        when IDLE =>
          busy    <= '0';
          cs_n    <= '1';
          mosi    <= '0';
          bit_cnt <= 0;

          if start = '1' then
            -- Reset timer and SCK so first edge is always HALF_PER cycles
            -- after CS_n asserts — deterministic regardless of start timing
            timer    <= 0;
            sclk_r   <= '0';

            -- Pre-load MSB onto MOSI before first rising SCK edge
            tx_shreg <= mosi_dat(DATA_W-2 downto 0) & '0';
            mosi     <= mosi_dat(DATA_W-1);
            cs_n     <= '0';
            busy     <= '1';
            state    <= TRANSFER;
          end if;

        when TRANSFER =>
          busy <= '1';

          if timer = HALF_PER - 1 then
            timer  <= 0;
            sclk_r <= not sclk_r;

            if sclk_r = '0' then
              -- SCK is about to go HIGH → sclk will be rising edge in the next clk
              -- Sample MISO in the same cycle as the edge — minimum latency
              rx_shreg <= rx_shreg(DATA_W-2 downto 0) & miso;

            else
              -- SCK is about to go LOW → falling edge
              -- Update MOSI for the next bit
              if bit_cnt = DATA_W - 1 then
                -- Last falling edge — stop SCK and finish
                sclk_r <= '0';
                state  <= DONE_ST;
                bit_cnt <= 0;
              else
                tx_shreg <= tx_shreg(DATA_W-2 downto 0) & '0';
                mosi     <= tx_shreg(DATA_W-1);
                bit_cnt  <= bit_cnt + 1;
              end if;
            end if;

          else
            timer <= timer + 1;
          end if;

        when DONE_ST =>
          cs_n     <= '1';
          mosi     <= '0';
          busy     <= '0';
          done     <= '1';
          miso_dat <= rx_shreg;
          state    <= IDLE;

      end case;
    end if;
  end process;

end Behavioral;