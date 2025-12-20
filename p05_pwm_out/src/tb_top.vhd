library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity tb_top is
generic(
    CLK_FREQ : integer := 100_000_000;
    PWM_FREQ : integer := 1000;
    N : integer := 2
);
end tb_top;

architecture Behavioral of tb_top is

    constant CLK_PERIOD : time      := 10 ns;
    signal   clk        : std_logic := '0';

    signal   led : std_logic_vector(1 downto 0);

begin

    pCLK_GEN: process begin
        clk <= '0'; wait for CLK_PERIOD/2;
        clk <= '1'; wait for CLK_PERIOD/2;
    end process;
    
    DUT: entity work.top
    generic map(
    CLK_FREQ => CLK_FREQ,
    PWM_FREQ => PWM_FREQ,
    N        => N
    )
    port map(
        clk => clk,
        led => led
    );


end Behavioral;