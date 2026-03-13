library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity btn_timer is
generic(
	CLK_FREQ : integer := 12_000_000
);
Port (
	clk  : in std_logic;
	btn0 : in std_logic;
	led  : out std_logic_vector(1 downto 0)
 );
end btn_timer;

architecture Behavioral of btn_timer is
	constant LIM2S    : integer := CLK_FREQ*2;
	constant LIM1S    : integer := CLK_FREQ;
	constant LIM500mS : integer := CLK_FREQ/2;
	constant LIM250mS : integer := CLK_FREQ/4;
	
	signal timer : integer range 0 to LIM2S := 0;
	signal timer_lim : integer range 0 to LIM2S := LIM2S;
	
	type t_state is (s_LIM2S, s_LIM1S, s_LIM500mS, s_LIM250mS);
	signal state : t_state := s_LIM2S;
	
    signal counter   : unsigned(1 downto 0) := "00";
	signal btn0_prev : std_logic := '1';
	signal btn0_debounced : std_logic := '0';
	
begin
	led <= std_logic_vector(counter);
	
	pTIMER : process(clk) 
	begin
		if rising_edge(clk) then
			if timer < timer_lim then
				timer <= timer + 1;
			else 	
				timer <= 0;
				counter <= counter + 1;
			end if;
		end if;
	end process;
	
	pBTN : process(clk)
	begin 
		if rising_edge(clk) then
			if btn0_debounced = '1' and btn0_prev = '0' then
				case state is
					when s_LIM2S =>
						timer_lim <= LIM1S;				
						state     <= s_LIM1S;
					when s_LIM1S =>
						timer_lim <= LIM500mS;
						state     <= s_LIM500mS;
					when s_LIM500mS =>
						timer_lim <= LIM250mS;
						state     <= s_LIM250mS;
					when s_LIM250mS =>
						timer_lim <= LIM2S;
						state     <= s_LIM2S;
				end case;
			end if;	
			btn0_prev <= btn0_debounced;
		end if;
	end process;
	
	inst_DEB: entity work.debouncer 
	generic map(
		CLK_FREQ => 12_000_000,
        DEBTIME_MS => 5,               
        ACTIVE_LOW => true       
	)
	Port map(
		clk    => clk,
		sig_in  => btn0,
		sig_out  => btn0_debounced
	);

end Behavioral;
