library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity top is
  generic(
    CLK_FREQ : integer := 12_000_000;
    PWM_FREQ : integer := 3000;
    N        : integer := 2
  );
  port(
    clk : in  std_logic;
    led : out std_logic_vector(1 downto 0)
  );
end top;

architecture Behavioral of top is
  -- duty inputs to the two PWMs
  signal duty_cycle0 : std_logic_vector(6 downto 0) := (others => '0');
  signal duty_cycle1 : std_logic_vector(6 downto 0) := (others => '0');

  -- 0..100 ramp with direction
  signal cnt      : integer range 0 to 100 := 0;
  signal dir      : std_logic := '0';  -- '0' up, '1' down
  signal cnt_next : integer range 0 to 100;
  signal dir_next : std_logic;

  -- exact 100 ms tick (@ CLK_FREQ)
  constant c_TIMER_100MS : integer := CLK_FREQ / 10;  -- 100 ms
  signal   timer         : integer range 0 to c_TIMER_100MS-1 := 0;
  signal   tick_100ms    : std_logic;
begin
  -- 100 ms tick: period = c_TIMER_100MS cycles (no +1 off-by-one)
  tick_100ms <= '1' when timer = c_TIMER_100MS-1 else '0';

  -- Direction update at the endpoints (no glitches)
  dir_next <= '1' when cnt = 100 else
              '0' when cnt = 0   else
              dir;

  -- Next count: step one in the chosen direction; clamp at [0..100]
  cnt_next <= cnt + 1 when (dir_next = '0' and cnt < 100) else
              cnt - 1 when (dir_next = '1' and cnt >   0) else
              cnt;

  -- Sequential section
  process(clk) begin
    if rising_edge(clk) then
      if tick_100ms = '1' then
        timer <= 0;
        cnt   <= cnt_next;
        dir   <= dir_next;
      else
        timer <= timer + 1;
      end if;

      -- drive duties (0..100 and 100..0)
      duty_cycle0 <= std_logic_vector(to_unsigned(cnt, 7));
      duty_cycle1 <= std_logic_vector(to_unsigned(100 - cnt, 7));
    end if;
  end process;

  -- Two PWM instances (glitch-free, double-buffered)
  PWM_inst0: entity work.pwm_out
    generic map(
      CLK_FREQ => CLK_FREQ,
      PWM_FREQ => PWM_FREQ
    )
    port map(
      clk        => clk,
      duty_cycle => duty_cycle0,
      pwm_out    => led(0)
    );

  PWM_inst1: entity work.pwm_out
    generic map(
      CLK_FREQ => CLK_FREQ,
      PWM_FREQ => PWM_FREQ
    )
    port map(
      clk        => clk,
      duty_cycle => duty_cycle1,
      pwm_out    => led(1)
    );
end Behavioral;
