library IEEE;
use IEEE.STD_LOGIC_1164.all;

--------------------------------------------------------------------------------
-- SPI Master — Mode 0 (CPOL=0, CPHA=0), no CS
--
-- Pure shift-register primitive. CS is the caller's responsibility.
-- One job: shift N_BITS over SPI at the requested rate.
--
-- Mode 0 timing:
--   SCK idle low
--   MOSI pre-loaded before the first rising SCK edge
--   MISO sampled on rising SCK edge
--   MOSI updated on falling SCK edge
--
-- Edge detection: act in the same cycle the edge occurs via timer compare,
-- no extra registered delay.
--------------------------------------------------------------------------------

entity spi_mode0_nocs is
  generic (
    CLK_FREQ  : integer := 12_000_000; -- system clock Hz
    SCLK_FREQ : integer := 1_000_000;  -- SCK frequency Hz
    N_BITS    : integer := 8           -- bits per transfer
  );
  port (
    clk     : in  std_logic;
    start   : in  std_logic;                        -- 1-cycle pulse
    busy    : out std_logic;
    done    : out std_logic;                        -- 1-cycle pulse
    tx_data : in  std_logic_vector(N_BITS-1 downto 0);
    rx_data : out std_logic_vector(N_BITS-1 downto 0);
    sclk    : out std_logic;
    mosi    : out std_logic;
    miso    : in  std_logic
  );
end spi_mode0_nocs;

architecture Behavioral of spi_mode0_nocs is

  constant HALF_PER : integer := CLK_FREQ / (SCLK_FREQ * 2);

  type t_state is (IDLE, TRANSFER, DONE_ST);
  signal state : t_state := IDLE;

  signal timer    : integer range 0 to HALF_PER - 1 := 0;
  signal sclk_r   : std_logic := '0';

  signal tx_shreg : std_logic_vector(N_BITS-1 downto 0) := (others => '0');
  signal rx_shreg : std_logic_vector(N_BITS-1 downto 0) := (others => '0');
  signal bit_cnt  : integer range 0 to N_BITS-1         := 0;

begin

  sclk <= sclk_r when state = TRANSFER else '0';

  p_MAIN : process (clk)
  begin
    if rising_edge(clk) then

      done <= '0';

      case state is

        when IDLE =>
          busy    <= '0';
          mosi    <= '0';
          bit_cnt <= 0;

          if start = '1' then
            timer    <= 0;
            sclk_r   <= '0';
            -- Pre-load MSB onto MOSI before first rising SCK edge
            tx_shreg <= tx_data(N_BITS-2 downto 0) & '0';
            mosi     <= tx_data(N_BITS-1);
            busy     <= '1';
            state    <= TRANSFER;
          end if;

        when TRANSFER =>
          busy <= '1';

          if timer = HALF_PER - 1 then
            timer  <= 0;
            sclk_r <= not sclk_r;

            if sclk_r = '0' then
              -- Rising edge: sample MISO
              rx_shreg <= rx_shreg(N_BITS-2 downto 0) & miso;

            else
              -- Falling edge: update MOSI
              if bit_cnt = N_BITS - 1 then
                state <= DONE_ST;
              else
                tx_shreg <= tx_shreg(N_BITS-2 downto 0) & '0';
                mosi     <= tx_shreg(N_BITS-1);
                bit_cnt  <= bit_cnt + 1;
              end if;
            end if;

          else
            timer <= timer + 1;
          end if;

        when DONE_ST =>
          mosi    <= '0';
          busy    <= '0';
          done    <= '1';
          rx_data <= rx_shreg;
          state   <= IDLE;

      end case;
    end if;
  end process;

end Behavioral;
