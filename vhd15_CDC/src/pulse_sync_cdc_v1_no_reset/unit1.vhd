----------------------------------------------------------------------------------
-- Engineer: Samet GUL
-- 
-- Create Date: 25.07.2026 21:36:32
--
-- Description: 
-- 
--
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.all;

entity unit1 is
  port (
    -- external interface
    clka      : in std_logic;
    number1_i : in std_logic_vector(7 downto 0);
    number2_i : in std_logic_vector(7 downto 0);
    sum_o     : out std_logic_vector(7 downto 0);
    enable    : in std_logic;
    ready     : out std_logic;

    -- unit 2 interface
    number1_o : out std_logic_vector(7 downto 0);
    number2_o : out std_logic_vector(7 downto 0);
    sum_i     : in std_logic_vector(7 downto 0);
    pulse_b_i : in std_logic;
    pulse_a_o : out std_logic
  );
end unit1;

architecture Behavioral of unit1 is
  signal enable_prev    : std_logic := '0';
  signal pulse_b_i_prev : std_logic := '0';
begin
  process (clka)
  begin
    if rising_edge(clka) then

      pulse_a_o <= '0'; -- Default value for pulse_a_o
      if enable = '1' and enable_prev = '0' then
        pulse_a_o <= '1'; -- Generate a pulse on pulse_a_o when enable goes high
        number1_o <= number1_i; -- Capture number1 when enable goes high
        number2_o <= number2_i; -- Capture number2 when enable goes high
      end if;

      ready <= '0'; -- Reset ready signal when pulse_b_i is low
      if pulse_b_i = '1' and pulse_b_i_prev = '0' then
        sum_o     <= sum_i; -- Capture the sum when pulse_b_i goes high
        ready     <= '1'; -- Indicate that the result is ready
      end if;

      enable_prev    <= enable; -- Store the previous value of enable
      pulse_b_i_prev <= pulse_b_i; -- Store the previous value of pulse_b_i
    end if;
  end process;

end Behavioral;
