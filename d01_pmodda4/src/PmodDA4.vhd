----------------------------------------------------------------------------------
-- Engineer:    Samet GUL
-- Email:       asam.gul@gmail.com
--
--
-- Create Date: 06.04.2026 20:20:10
-- Description: PmodDA4 AD5628 Driver
-- 
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.all;

entity PmodDA4 is
  generic (
    CLK_FREQ  : integer := 100_000_000; -- system clock frequency (Hz)
    SCLK_FREQ : integer := 25_000_000 -- desired SCK frequency   (Hz)
  );
  port (
    clk      : in std_logic;
    start    : in std_logic; -- 1-cycle pulse: begin transaction
    da4_done : out std_logic; -- 1-cycle pulse: transaction complete
    CHANNEL  : std_logic_vector(3 downto 0) := "0000"; -- CHA_A = 0000 ... CHA_H = 0111, ALL_CHA = 1111
    dac_val  : in std_logic_vector(11 downto 0); -- data to transmit (MSB first)
    sclk     : out std_logic;
    mosi     : out std_logic;
    cs_n     : out std_logic -- chip select, active-low
  );
end PmodDA4;

architecture Behavioral of PmodDA4 is

  signal start_reg    : std_logic := '0';
  signal busy_reg     : std_logic := '0';
  signal done_reg     : std_logic := '0';
  signal da4_done_reg : std_logic := '0';

  type t_state is (sIDLE, sINIT_REF, sTRANSFER);
  signal state : t_state := sIDLE;

  signal init_flag : std_logic := '0';

  signal write_data : std_logic_vector(31 downto 0) := (others => '0');

begin

  da4_done <= da4_done_reg;

  process (clk) begin
    if rising_edge(clk) then
      da4_done_reg <= '0';
      case state is
        when sIDLE =>
          if (start = '1') then
            if init_flag = '0' then
              start_reg  <= '1';
              state      <= sINIT_REF;
              write_data <= "0000" & "1000" & "0000" & "0000" & "0000" & "0000" & "0000" & "0001";
            else
              start_reg  <= '1';
              state      <= sTRANSFER;
              write_data <= "0000" & "0011" & CHANNEL & dac_val & "0000" & "0000";
            end if;
          end if;
        when sINIT_REF =>
          start_reg    <= '0';
          if (done_reg = '1') then
            start_reg  <= '1';
            init_flag  <= '1';
            state      <= sTRANSFER;
            write_data <= "0000" & "0011" & CHANNEL & dac_val & "0000" & "0000";
          end if;
        when sTRANSFER =>
          start_reg    <= '0';
          if (done_reg = '1') then
            state        <= sIDLE;
            da4_done_reg <= '1';

          end if;
      end case;
    end if;
  end process;

  -- it works with SPI MODE 2
  inst_SPI2 : entity work.spi_all_modes
    generic map(
      CLK_FREQ  => CLK_FREQ,
      SCLK_FREQ => SCLK_FREQ,
      DATA_W    => 32,
      CPOL      => '1',
      CPHA      => '0'
    )
    port map
    (
      clk      => clk,
      start    => start_reg,
      busy     => open,
      done     => done_reg,
      mosi_dat => write_data,
      miso_dat => open,
      sclk     => sclk,
      mosi     => mosi,
      miso     => '0',
      cs_n     => cs_n
    );
end Behavioral;
