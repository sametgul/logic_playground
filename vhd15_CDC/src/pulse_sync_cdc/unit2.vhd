----------------------------------------------------------------------------------
-- Engineer: Samet GUL
-- 
-- Create Date: 25.07.2026 21:47:32
--
-- Description: 
-- 
--
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.all;
use ieee.NUMERIC_STD.all;

entity unit2 is
  port (
    clkb      : in std_logic;
    number1_i : in std_logic_vector(7 downto 0);
    number2_i : in std_logic_vector(7 downto 0);
    sum_o     : out std_logic_vector(7 downto 0);
    pulse_b_i : in std_logic;
    pulse_a_o : out std_logic
  );
end unit2;

architecture Behavioral of unit2 is
  signal pulse_b_i_prev : std_logic := '0';
begin
  process (clkb)
  begin
    if rising_edge(clkb) then

      pulse_a_o <= '0'; -- Default value for pulse_a_o
      if pulse_b_i = '1' and pulse_b_i_prev = '0' then
        sum_o     <= std_logic_vector(unsigned(number1_i) + unsigned(number2_i)); -- Capture the sum when pulse_b_i goes high
        pulse_a_o <= '1'; -- Indicate that the result is ready
      end if;

      pulse_b_i_prev <= pulse_b_i; -- Store the previous value of pulse_b_i
    end if;
  end process;

end Behavioral;
