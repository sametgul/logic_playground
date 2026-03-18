library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;

entity rgb_controller is
  generic (
    CLK_FREQ : integer := 12_000_000; -- Hz
    PWM_FREQ : integer := 1_000; -- Hz
    N        : integer := 14 -- must satisfy: N >= ceil(log2(PWM_PERIOD + 1))
    -- PWM_PERIOD = CLK_FREQ / PWM_FREQ
    -- e.g. 12 MHz / 1 kHz = 12_000 → N >= 14
  );
  port (
    clk    : in std_logic;
    R_i8   : in std_logic_vector(7 downto 0); -- 8-bit red   value (0..255)
    G_i8   : in std_logic_vector(7 downto 0); -- 8-bit green value (0..255)
    B_i8   : in std_logic_vector(7 downto 0); -- 8-bit blue  value (0..255)
    led0_r : out std_logic;
    led0_g : out std_logic;
    led0_b : out std_logic
  );
end rgb_controller;

architecture Behavioral of rgb_controller is

  constant PWM_PERIOD : integer := CLK_FREQ / PWM_FREQ;

  signal duty_red   : integer range 0 to PWM_PERIOD / 2 := 0;
  signal duty_green : integer range 0 to PWM_PERIOD / 2 := 0;
  signal duty_blue  : integer range 0 to PWM_PERIOD / 2 := 0;

  signal pwm_red   : std_logic;
  signal pwm_green : std_logic;
  signal pwm_blue  : std_logic;

begin

  -- Map 8-bit color values (0..255) to duty range (0..PWM_PERIOD/2)
  -- Capped at 50% duty cycle as required by Digilent for CMOD A7 RGB LED
  -- PWM_PERIOD/2 is a compile-time constant so this is a single DSP48 multiply
  duty_red   <= to_integer(unsigned(R_i8)) * (PWM_PERIOD / 2) / 255;
  duty_green <= to_integer(unsigned(G_i8)) * (PWM_PERIOD / 2) / 255;
  duty_blue  <= to_integer(unsigned(B_i8)) * (PWM_PERIOD / 2) / 255;

  -- CMOD A7 RGB LED is active-low: invert PWM output so '1' duty = brighter
  led0_r <= not pwm_red;
  led0_g <= not pwm_green;
  led0_b <= not pwm_blue;

  inst_R : entity work.pwm_tick_based
    generic map(
      CLK_FREQ => CLK_FREQ,
      PWM_FREQ => PWM_FREQ,
      N        => N
    )
    port map
    (
      clk        => clk,
      duty_cycle => std_logic_vector(to_unsigned(duty_red, N)),
      pwm_out    => pwm_red
    );

  inst_G : entity work.pwm_tick_based
    generic map(
      CLK_FREQ => CLK_FREQ,
      PWM_FREQ => PWM_FREQ,
      N        => N
    )
    port map
    (
      clk        => clk,
      duty_cycle => std_logic_vector(to_unsigned(duty_green, N)),
      pwm_out    => pwm_green
    );

  inst_B : entity work.pwm_tick_based
    generic map(
      CLK_FREQ => CLK_FREQ,
      PWM_FREQ => PWM_FREQ,
      N        => N
    )
    port map
    (
      clk        => clk,
      duty_cycle => std_logic_vector(to_unsigned(duty_blue, N)),
      pwm_out    => pwm_blue
    );

end Behavioral;