library IEEE;
use IEEE.STD_LOGIC_1164.ALL;


entity tb_debouncer is
generic(
    CLK_FREQ   : integer := 1000;    -- Hz
    DEBTIME_MS : integer := 5;             -- ms   
    ACTIVE_LOW : boolean := true                    
);
end tb_debouncer;

architecture Behavioral of tb_debouncer is

    constant CLK_PERIOD : time      := 1 ms;  
    signal   clk        : std_logic := '1';
    
    signal sig_in  : std_logic := '1';
    signal sig_out : std_logic;

begin

    pSTIMULI: process begin
        wait for 5 ms;   
        sig_in <= '0';
        
        wait for 3 ms;
        sig_in <= '1';
        
        wait for 2 ms;
        sig_in <= '0';
        
        wait for 5 ms;
        sig_in <= '0';
        
        wait for 2 ms;
        sig_in <= '1';
        wait for 6 ms;
        
        assert false
        report "SIM DONE"
        severity failure;
    end process;

    pCLK_GEN: process begin
        clk <= '0';
        wait for CLK_PERIOD/2;
        clk <= '1';
        wait for CLK_PERIOD/2;
    end process;
    
    DUT: entity work.debouncer
    generic map(
        CLK_FREQ   => CLK_FREQ  ,
        DEBTIME_MS => DEBTIME_MS,
        ACTIVE_LOW => ACTIVE_LOW
    )
    port map(
        clk     => clk   ,
        sig_in  => sig_in, 
        sig_out => sig_out
    );

end Behavioral;