----------------------------------------------------------------------------------
-- Engineer: Samet GUL
--
-- Create Date: 25.07.2026 22:07:32
-- Description: Testbench for the top CDC units
--
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.all;

entity tb_top_cdc is
  --  Port ( );
end tb_top_cdc;

architecture Behavioral of tb_top_cdc is

  signal clka      : std_logic                    := '0';
  signal clkb      : std_logic                    := '0';
  signal number1_i : std_logic_vector(7 downto 0) := (others => '0');
  signal number2_i : std_logic_vector(7 downto 0) := (others => '0');
  signal sum_o     : std_logic_vector(7 downto 0);
  signal enable    : std_logic := '0';
  signal ready     : std_logic;

  constant CLK_A_PERIOD : time := 7.5 ns; -- Clock A period
  constant CLK_B_PERIOD : time := 10 ns; -- Clock B period

begin

    p_STIMULI : process
    begin
        -- Stimulus for the testbench
        wait for CLK_A_PERIOD * 2;
        number1_i <= "00000001"; -- Set number1_i to 1
        number2_i <= "00000010"; -- Set number2_i to 2
        enable    <= '1'; -- Enable the operation
        wait for CLK_A_PERIOD;
        enable    <= '0'; -- Disable the operation
        wait until ready = '1'; -- Wait until the result is ready

        assert sum_o = "00000011"
            report "Test failed: Expected sum is 3"
            severity error; -- Check if the sum is correct

        wait for CLK_A_PERIOD * 5;

        assert false report "Simulation finished" severity failure;

    end process;

    p_CLK_A : process
    begin
        clka <= '0';
        wait for CLK_A_PERIOD / 2;
        clka <= '1';
        wait for CLK_A_PERIOD / 2;
    end process;

    p_CLK_B : process
    begin
        clkb <= '0';
        wait for CLK_B_PERIOD / 2;
        clkb <= '1';
        wait for CLK_B_PERIOD / 2;
    end process;

  DUT : entity work.top_cdc_units
    port map
    (
      clka      => clka,
      clkb      => clkb,
      number1_i => number1_i,
      number2_i => number2_i,
      sum_o     => sum_o,
      enable    => enable,
      ready     => ready
    );
end Behavioral;