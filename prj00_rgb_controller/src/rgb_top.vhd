library IEEE;
use IEEE.STD_LOGIC_1164.all;

entity rgb_top is
  generic (
    CLK_FREQ : integer := 12_000_000
  );
  port (
    clk    : in  std_logic;
    led0_r : out std_logic;
    led0_g : out std_logic;
    led0_b : out std_logic
  );
end rgb_top;

architecture Behavioral of rgb_top is

  constant TIM_LIM_1S : integer := CLK_FREQ;
  signal timer        : integer range 0 to TIM_LIM_1S - 1 := 0;
  signal color_count  : integer range 0 to 8              := 0;

  signal R_i8 : std_logic_vector(7 downto 0);
  signal G_i8 : std_logic_vector(7 downto 0);
  signal B_i8 : std_logic_vector(7 downto 0);

begin

  -- Timer: increments color_count every second
  pTIMER : process (clk)
  begin
    if rising_edge(clk) then
      if timer = TIM_LIM_1S - 1 then
        timer <= 0;
        if color_count = 8 then
          color_count <= 0;
        else
          color_count <= color_count + 1;
        end if;
      else
        timer <= timer + 1;
      end if;
    end if;
  end process;

  -- Color lookup: maps color_count to RGB values
  -- Combinational — color_count changes → R/G/B update immediately
  pCOLOR : process (color_count)
  begin
    case color_count is
      when 0 => R_i8 <= x"FF"; G_i8 <= x"00"; B_i8 <= x"00"; -- RED
      when 1 => R_i8 <= x"00"; G_i8 <= x"FF"; B_i8 <= x"00"; -- GREEN
      when 2 => R_i8 <= x"00"; G_i8 <= x"00"; B_i8 <= x"FF"; -- BLUE
      when 3 => R_i8 <= x"FF"; G_i8 <= x"FF"; B_i8 <= x"FF"; -- WHITE
      when 4 => R_i8 <= x"FF"; G_i8 <= x"FF"; B_i8 <= x"00"; -- YELLOW
      when 5 => R_i8 <= x"00"; G_i8 <= x"FF"; B_i8 <= x"FF"; -- CYAN
      when 6 => R_i8 <= x"FF"; G_i8 <= x"00"; B_i8 <= x"FF"; -- MAGENTA
      when 7 => R_i8 <= x"FF"; G_i8 <= x"60"; B_i8 <= x"00"; -- ORANGE
      when 8 => R_i8 <= x"40"; G_i8 <= x"40"; B_i8 <= x"40"; -- DIM WHITE
      when others => R_i8 <= x"00"; G_i8 <= x"00"; B_i8 <= x"00"; -- off
    end case;
  end process;

  inst_RGB : entity work.rgb_controller
    port map(
      clk    => clk,
      R_i8   => R_i8,
      G_i8   => G_i8,
      B_i8   => B_i8,
      led0_r => led0_r,
      led0_g => led0_g,
      led0_b => led0_b
    );

end Behavioral;