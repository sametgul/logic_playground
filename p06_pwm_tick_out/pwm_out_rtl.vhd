library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity pwm_out_rtl is
generic(
    CLK_FREQ : integer := 40_000_000; -- 40 MHz
    PWM_FREQ : integer := 200_000;    -- 200 kHz
    N        : integer := 8           -- should be changed according to high time step size
);
port(
    clk        : in  std_logic;
    duty_cycle : in  std_logic_vector(N-1 downto 0); -- 0..200 for 40 MHz and 200 kHz
    pwm_out    : out std_logic
);
end pwm_out_rtl;

architecture Behavioral of pwm_out_rtl is
    constant PWM_PERIOD : integer := CLK_FREQ / PWM_FREQ; -- 200 ticks for 40 MHz and 200 kHz

    signal timer        : integer range 0 to PWM_PERIOD-1 := 0;
    signal duty_int     : integer range 0 to PWM_PERIOD   := 0;
begin

    -- Clamp duty cycle safely
    duty_int <= PWM_PERIOD when (to_integer(unsigned(duty_cycle)) > PWM_PERIOD)
                           else to_integer(unsigned(duty_cycle));

    -- Single clean PWM process
    process(clk)
    begin
        if rising_edge(clk) then

            -- PWM output compare
            if timer < duty_int then
                pwm_out <= '1';
            else
                pwm_out <= '0';
            end if;

            -- Timer update
            if timer = PWM_PERIOD-1 then
                timer <= 0;
            else
                timer <= timer + 1;
            end if;

        end if;
    end process;

end Behavioral;
