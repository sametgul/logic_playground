library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity debouncer is
generic(
    CLK_FREQ   : integer := 12_000_000;    -- Hz
    DEBTIME_MS : integer := 5;             -- ms   
    ACTIVE_LOW : boolean := true           
);
port(
    clk     : in  std_logic;
    sig_in  : in  std_logic;
    sig_out : out std_logic
);
end debouncer;

architecture Behavioral of debouncer is

    type t_state is (sINIT, sONE, sONEtoZERO, sZERO, sZEROtoONE);
    signal state : t_state := sINIT;
    
    signal tim_en  : std_logic := '0';
    signal tim_tick: std_logic := '0';
    
    constant TIM_LIM : integer := CLK_FREQ/(1000)*DEBTIME_MS;
    signal   timer   : integer range 0 to TIM_LIM-1 := 0;
begin

    pMAIN: process(clk) begin
        if rising_edge(clk) then
            case state is 
                when sINIT =>
                    if ACTIVE_LOW = true then
                            state   <= sONE;
                            sig_out <= '1';
                    else
                            state   <= sZERO;
                            sig_out <= '0';
                    end if;
                    
                when sONE =>
                    sig_out <= '1';
                    
                    if(sig_in = '0') then
                        state  <= sONEtoZERO;
                        tim_en <= '1';
                    end if;
                    
                when sONEtoZERO =>
                    sig_out <= '1';
                    
                    if(sig_in = '1') then
                        state   <= sONE;
                        tim_en  <= '0';
                    elsif(tim_tick = '1') then
                        state   <= sZERO;
                        tim_en  <= '0';
                    end if;
                    
                
                when sZERO      =>
                    sig_out <= '0';
                    
                    if(sig_in = '1') then
                        state  <= sZEROtoONE;
                        tim_en <= '1';
                    end if;
                    
                when sZEROtoONE =>
                    sig_out <= '0';
                    
                    if(sig_in = '0') then
                        state   <= sZERO;
                        tim_en  <= '0';
                    elsif(tim_tick = '1') then
                        state   <= sONE;
                        tim_en  <= '0';
                    end if;
            end case;  
        end if;
    end process;
    
    pTIMER: process(clk) begin
        if rising_edge(clk) then
            if(tim_en = '1') then
                if(timer = TIM_LIM-1) then
                    timer    <= 0;
                    tim_tick <= '1';      
                else
                    timer    <= timer + 1;
                    tim_tick <= '0';
                end if;                
            else
                timer    <= 0;
                tim_tick <= '0';
            end if;
        end if;
    end process;

end Behavioral;
