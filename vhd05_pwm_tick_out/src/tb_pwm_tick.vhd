library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity tb_pwm_tick is
    generic(
        CLK_FREQ : integer := 10;  -- Hz  → CLK_PERIOD = 100 ms
        PWM_FREQ : integer := 1;   -- Hz  → PWM_PERIOD = 10 cycles
        N        : integer := 4    -- 4 bits → range 0..15, covers PWM_PERIOD=10
    );
end tb_pwm_tick;

architecture Behavioral of tb_pwm_tick is

    constant CLK_PERIOD : time    := 1 sec / CLK_FREQ;   -- 100 ms
    constant PWM_PERIOD : integer := CLK_FREQ / PWM_FREQ; -- 10 cycles

    signal clk        : std_logic := '0';
    signal duty_cycle : std_logic_vector(N-1 downto 0) := (others => '0');
    signal pwm_out    : std_logic;

begin

    -- Clock generation
    pCLK: process
    begin
        clk <= '0'; wait for CLK_PERIOD / 2;
        clk <= '1'; wait for CLK_PERIOD / 2;
    end process;

    pSTIMULI: process
    begin

        -- ----------------------------------------------------------------
        -- Test 1: Sweep duty cycle from 0% to 100% in steps
        -- Wait 2 full PWM periods per step to observe stable output
        -- ----------------------------------------------------------------
        report "TEST 1: Duty cycle sweep 0% to 100%";
        for i in 0 to PWM_PERIOD loop
            duty_cycle <= std_logic_vector(to_unsigned(i, N));
            wait for 2 * PWM_PERIOD * CLK_PERIOD;
        end loop;

        -- ----------------------------------------------------------------
        -- Test 2: Mid-period duty change
        -- Change duty_cycle in the middle of a PWM period and verify
        -- the output does not glitch — new value takes effect next period.
        -- ----------------------------------------------------------------
        report "TEST 2: Mid-period duty change";
        duty_cycle <= std_logic_vector(to_unsigned(3, N)); -- 30%
        wait for (PWM_PERIOD / 2) * CLK_PERIOD;            -- wait half a period
        duty_cycle <= std_logic_vector(to_unsigned(7, N)); -- change to 70% mid-period
        wait for 3 * PWM_PERIOD * CLK_PERIOD;              -- observe 3 full periods

        -- ----------------------------------------------------------------
        -- Test 3: Clamping — value above PWM_PERIOD
        -- N=4 allows up to 15, PWM_PERIOD=10, so 15 should clamp to 100%
        -- ----------------------------------------------------------------
        report "TEST 3: Clamping above PWM_PERIOD";
        duty_cycle <= std_logic_vector(to_unsigned(15, N)); -- above PWM_PERIOD → clamp
        wait for 3 * PWM_PERIOD * CLK_PERIOD;

        -- ----------------------------------------------------------------
        -- Test 4: Edge cases — 0% and 100%
        -- ----------------------------------------------------------------
        report "TEST 4: Edge cases";
        duty_cycle <= (others => '0');                               -- 0%
        wait for 2 * PWM_PERIOD * CLK_PERIOD;
        duty_cycle <= std_logic_vector(to_unsigned(PWM_PERIOD, N)); -- 100%
        wait for 2 * PWM_PERIOD * CLK_PERIOD;

        assert FALSE
            report "SIM DONE"
            severity FAILURE;

    end process;

    iPWM: entity work.pwm_tick_based
    generic map(
        CLK_FREQ   => CLK_FREQ,
        PWM_FREQ   => PWM_FREQ,
        N          => N
    )
    port map(
        clk        => clk,
        duty_cycle => duty_cycle,
        pwm_out    => pwm_out
    );

end Behavioral;