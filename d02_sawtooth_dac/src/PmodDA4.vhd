----------------------------------------------------------------------------------
-- Engineer:    Samet GUL
-- Email:       asam.gul@gmail.com
--
-- Create Date: 14.04.2026
-- Description: PmodDA4 AD5628 Driver - Fastest version
--              Uses spi_cs_timing at 50 MHz SCLK (requires 100 MHz sys clock)
--              CS timing meets AD5628 t4 (20 ns) and t8 (20 ns) constraints.
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.all;

entity PmodDA4 is
  generic (
    CLK_FREQ  : integer := 100_000_000; -- system clock frequency (Hz)
    SCLK_FREQ : integer :=  50_000_000  -- desired SCK frequency   (Hz)
  );
  port (
    clk      : in  std_logic;
    start    : in  std_logic;                      -- 1-cycle pulse: begin transaction
    busy     : out std_logic;                      -- high while transaction in progress
    da4_done : out std_logic;                      -- 1-cycle pulse: transaction complete
    CHANNEL  : in  std_logic_vector(3 downto 0);  -- 0000=CH_A .. 0111=CH_H, 1111=ALL
    dac_val  : in  std_logic_vector(11 downto 0); -- 12-bit DAC value (MSB first)
    sclk     : out std_logic;
    mosi     : out std_logic;
    cs_n     : out std_logic                       -- chip select, active-low
  );
end PmodDA4;

architecture Behavioral of PmodDA4 is

  signal spi_start    : std_logic := '0';
  signal spi_done     : std_logic := '0';
  signal da4_spi_done : std_logic := '0';

  type t_state is (sIDLE, sINIT_REF, sTRANSFER);
  signal state : t_state := sIDLE;

  signal init_flag  : std_logic                     := '0';
  signal write_data : std_logic_vector(31 downto 0) := (others => '0');

begin

  da4_done <= da4_spi_done;
  busy     <= '0' when state = sIDLE else '1';

  process (clk) begin
    if rising_edge(clk) then
      da4_spi_done <= '0';
      spi_start    <= '0';
      case state is

        when sIDLE =>
          if start = '1' then
            spi_start <= '1';
            if init_flag = '0' then
              state      <= sINIT_REF;
              write_data <= x"08000001"; -- enable internal 2.5 V reference
            else
              state      <= sTRANSFER;
              write_data <= "0000" & "0011" & CHANNEL & dac_val & x"00";
            end if;
          end if;

        when sINIT_REF =>
          if spi_done = '1' then
            spi_start  <= '1';
            init_flag  <= '1';
            state      <= sTRANSFER;
            write_data <= "0000" & "0011" & CHANNEL & dac_val & x"00";
          end if;

        when sTRANSFER =>
          if spi_done = '1' then
            state        <= sIDLE;
            da4_spi_done <= '1';
          end if;

      end case;
    end if;
  end process;

  -- SPI Mode 2 (CPOL=1, CPHA=0): AD5628 samples MOSI on falling SCLK edge
  inst_SPI : entity work.spi_cs_timing
    generic map(
      CLK_FREQ       => CLK_FREQ,
      SCLK_FREQ      => SCLK_FREQ,
      DATA_W         => 32,
      CPOL           => '1',
      CPHA           => '0',
      CS_SETUP_TICKS => 1, -- 1 cycle → t4 = 20 ns (pipeline adds +1), meets ≥ 13 ns
      CS_IDLE_TICKS  => 0  -- 0 explicit → t8 = 20 ns (pipeline adds +2), meets ≥ 15 ns
    )
    port map(
      clk      => clk,
      start    => spi_start,
      busy     => open,
      done     => spi_done,
      mosi_dat => write_data,
      miso_dat => open,
      sclk     => sclk,
      mosi     => mosi,
      miso     => '0',
      cs_n     => cs_n
    );

end Behavioral;
