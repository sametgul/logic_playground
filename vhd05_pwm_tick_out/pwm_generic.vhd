library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity pwm_gen is
generic(
    CLK_FREQ : integer := 40_000_000; -- Hz
    PWM_FREQ : integer := 200_000;    -- Hz
    N        : integer := 8           -- must satisfy: N >= ceil(log2(PWM_PERIOD + 1))
                                      -- PWM_PERIOD = CLK_FREQ / PWM_FREQ
                                      -- e.g. 40 MHz / 200 kHz = 200 → N >= 8
);
port(
    clk        : in  std_logic;
    duty_cycle : in  std_logic_vector(N-1 downto 0); -- 0 = 0%, PWM_PERIOD = 100%
    pwm_out    : out std_logic
);
end pwm_gen;

architecture Behavioral of pwm_gen is

    constant PWM_PERIOD : integer := CLK_FREQ / PWM_FREQ;

    signal timer        : integer range 0 to PWM_PERIOD-1 := 0;
    signal duty_int     : integer range 0 to PWM_PERIOD   := 0;
    signal duty_latched : integer range 0 to PWM_PERIOD   := 0;

begin

    -- Combinational clamp: values above PWM_PERIOD are saturated to PWM_PERIOD (100%)
    duty_int <= PWM_PERIOD when (to_integer(unsigned(duty_cycle)) > PWM_PERIOD)
                           else to_integer(unsigned(duty_cycle));

    process(clk)
    begin
        if rising_edge(clk) then

            -- Latch duty only at the start of each period.
            -- This prevents mid-period glitches when duty_cycle changes:
            -- a new duty value always takes effect on the next clean period boundary.
            if timer = 0 then
                duty_latched <= duty_int;
            end if;

            -- PWM output compare against latched duty
            -- duty_latched = 0          → always LOW  (0%)
            -- duty_latched = PWM_PERIOD → always HIGH (100%)
            if timer < duty_latched then
                pwm_out <= '1';
            else
                pwm_out <= '0';
            end if;

            -- Free-running period counter
            if timer = PWM_PERIOD-1 then
                timer <= 0;
            else
                timer <= timer + 1;
            end if;

        end if;
    end process;

end Behavioral;