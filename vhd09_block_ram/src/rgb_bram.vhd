library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;

entity rgb_bram is
  generic (
    CLK_FREQ : integer := 12_000_000
  );
  port (
    clk    : in  std_logic;
    led0_r : out std_logic;
    led0_g : out std_logic;
    led0_b : out std_logic
  );
end rgb_bram;

architecture Behavioral of rgb_bram is

  signal ram_addr : integer range 0 to 255 := 0;
  signal ram_dout : std_logic_vector(23 downto 0);

  signal Red_i8   : std_logic_vector(7 downto 0);
  signal Green_i8 : std_logic_vector(7 downto 0);
  signal Blue_i8  : std_logic_vector(7 downto 0);

  -- 20 ms step: each LUT entry is held for 20 ms before advancing
  -- At 12 MHz: 12_000_000 / 1000 * 20 = 240_000 cycles
  -- Full 256-entry rainbow cycle takes 256 * 20 ms = 5.12 seconds
  constant TIM_LIM_20mS : integer := CLK_FREQ / 1000 * 20;
  signal timer : integer range 0 to TIM_LIM_20mS - 1 := 0;

begin

  -- Unpack 24-bit BRAM output into separate R, G, B bytes
  -- ram_dout is valid one cycle after ram_addr changes (1-cycle BRAM latency)
  -- At 20 ms per step this 1-cycle glitch is completely invisible
  Red_i8   <= ram_dout(23 downto 16);
  Green_i8 <= ram_dout(15 downto 8);
  Blue_i8  <= ram_dout(7  downto 0);

  -- Address counter: steps through BRAM every 20 ms
  -- ram_addr wraps naturally at 255 due to integer range constraint
  pMAIN : process (clk)
  begin
    if rising_edge(clk) then
      if timer = TIM_LIM_20mS - 1 then
        timer    <= 0;
        ram_addr <= ram_addr + 1;
      else
        timer <= timer + 1;
      end if;
    end if;
  end process;

  inst_BRAM : entity work.rainbow_rom
    port map(
      clka  => clk,
      addra => std_logic_vector(to_unsigned(ram_addr, 8)),
      douta => ram_dout
    );

  inst_RGB : entity work.rgb_controller
    port map(
      clk    => clk,
      R_i8   => Red_i8,
      G_i8   => Green_i8,
      B_i8   => Blue_i8,
      led0_r => led0_r,
      led0_g => led0_g,
      led0_b => led0_b
    );

end Behavioral;