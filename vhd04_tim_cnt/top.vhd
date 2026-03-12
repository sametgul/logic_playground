library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity top is
generic(
    CLK_FREQ : integer := 12_000_000
);
port(
    clk: in std_logic;
    btn : in std_logic_vector(1 downto 0);
    led : out std_logic_vector(1 downto 0)
);
end top;

architecture Behavioral of top is
    constant TICK_250mS : integer := CLK_FREQ/4;
    constant TICK_500mS : integer := CLK_FREQ/2;
    constant TICK_1S    : integer := CLK_FREQ;
    constant TICK_2S    : integer := CLK_FREQ*2;

    signal counter   : unsigned(1 downto 0) := "00";
    
    signal timer_lim : integer := TICK_250mS;
    signal timer     : integer range 0 to TICK_2S := 0;   
    
    type LIM_STATES is (s_250mS, s_500mS, s_1S, s_2S);
    signal lim_state : LIM_STATES := s_250mS; 
    
    signal btn_prev : std_logic_vector(1 downto 0) := "00"; 
begin
    led <= std_logic_vector(counter);
    
    p_COUNTER: process(clk) 
    begin
        if rising_edge(clk) then
            if(timer < timer_lim) then
                timer <= timer+1;
            else
                counter <= counter + 1; 
                timer   <= 0;
            end if;
        end if;
    end process;
    
    p_LIM_CHOICE: process(clk)
    begin
        if rising_edge(clk) then
            if (btn(0) = '1' and btn_prev(0) = '0') then
                case lim_state is 
                    when s_250mS => 
                        timer_lim <= TICK_500mS; 
                        lim_state <= s_500mS; 
                    when s_500mS => 
                        timer_lim <= TICK_1S; 
                        lim_state <= s_1S; 
                    when s_1S => 
                        timer_lim <= TICK_2S; 
                        lim_state <= s_2S; 
                    when others => null;
                end case;
        
            elsif (btn(1) = '1' and btn_prev(1) = '0') then
                case lim_state is 
                    when s_500mS => 
                        timer_lim <= TICK_250mS; 
                        lim_state <= s_250mS; 
                    when s_1S => 
                        timer_lim <= TICK_500mS; 
                        lim_state <= s_500mS; 
                    when s_2S => 
                        timer_lim <= TICK_1S;
                        lim_state <= s_1S; 
                    when others => null;
                end case;
            end if;
        
            btn_prev <= btn;
        end if;

    end process;

end Behavioral;
