library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity tb_spbram is
generic (
WIDTH       : integer := 16;
DEPTH       : integer := 10;
read_type   : string := "WRITE_FIRST";
LAT         : string := "1_CLK"
);
end tb_spbram;

architecture Behavioral of tb_spbram is

    signal clk     : std_logic := '0';
    signal we_i    : std_logic := '0';
    signal addr_i  : std_logic_vector (DEPTH-1 downto 0) := (others => '0');
    signal din_i   : std_logic_vector (WIDTH-1 downto 0) := (others => '0');
    signal dout_o  : std_logic_vector (WIDTH-1 downto 0);
    
    constant c_CLK_PERIOD : time := 10 ns;

begin
    
    pSTIMULI: process begin
        wait for c_CLK_PERIOD*5;
        din_i <= x"ABCD";
        we_i  <= '1';
        wait for c_CLK_PERIOD*3;
        din_i <= x"0123";
        we_i  <= '1';
        wait for c_CLK_PERIOD*3;
        
        assert false
            report "SIM DONE"
            severity failure;
    end process;
    
    pCLK: process begin
        clk <= '0'; wait for c_CLK_PERIOD/2;
        clk <= '1'; wait for c_CLK_PERIOD/2;
    end process;
    

    DUT: entity work.spbram
    generic map(
    WIDTH       => WIDTH,
    DEPTH       => DEPTH,
    read_type   => read_type,
    LAT         => LAT
    )
    port map(
    clk     => clk    ,
    we_i    => we_i   ,
    addr_i  => addr_i ,
    din_i   => din_i  ,
    dout_o  => dout_o 
    );


end Behavioral;
