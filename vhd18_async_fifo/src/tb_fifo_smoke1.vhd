-- Smoke test 1: four words through the FIFO, read back one at a time.
-- Checks that the Xilinx FIFO model loads and that the data comes out in order.
library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;

entity tb_fifo_smoke1 is
  --  Port ( );
end tb_fifo_smoke1;

architecture Behavioral of tb_fifo_smoke1 is

  signal wr_clk : std_logic := '0';
  signal rd_clk : std_logic := '0';
  signal din    : std_logic_vector(7 downto 0) := (others => '0');
  signal wr_en  : std_logic := '0';
  signal rd_en  : std_logic := '0';
  signal dout   : std_logic_vector(7 downto 0);
  signal full   : std_logic;
  signal empty  : std_logic;

  -- handshaking flags of the FIFO (not checked by this test, only visible in the waveform)
  signal wr_ack    : std_logic; -- wr_clk: the write was accepted
  signal overflow  : std_logic; -- wr_clk: wr_en while full, the write was rejected
  signal valid     : std_logic; -- rd_clk: dout holds valid data
  signal underflow : std_logic; -- rd_clk: rd_en while empty

  constant CLK_PERIOD1 : time := 10 ns;
  constant CLK_PERIOD2 : time := 27 ns;

  -- words to push through the FIFO: distinct patterns so a swapped or repeated word is visible
  type t_data is array (0 to 3) of std_logic_vector(7 downto 0);
  constant C_DATA : t_data := (x"A5", x"3C", x"7E", x"01");

  signal rd_done : boolean := false;
  signal errors  : integer := 0; -- driven only by process_read

begin

    -- Write side: everything is synchronous to wr_clk and assigned right after the edge
    process_write : process
    begin
        -- the model has no reset pin, give it time to finish its internal power-on reset
        for i in 1 to 50 loop
            wait until rising_edge(wr_clk);
        end loop;
        assert full = '0' report "full is not low after start-up" severity error;

        -- four back-to-back writes, one per wr_clk
        for i in 0 to 3 loop
            wait until rising_edge(wr_clk);
            din   <= C_DATA(i);
            wr_en <= '1';
        end loop;
        wait until rising_edge(wr_clk); -- the FIFO samples the last word on this edge
        wr_en <= '0';
        wait;
    end process process_write;

    -- Read side: everything is synchronous to rd_clk, one word at a time
    process_read : process
    begin
        for i in 0 to 3 loop
            wait until rising_edge(rd_clk) and empty = '0';
            rd_en <= '1';
            wait until rising_edge(rd_clk); -- the FIFO samples rd_en on this edge
            rd_en <= '0';
            wait until rising_edge(rd_clk); -- standard FIFO, read latency 1: dout is valid one rd_clk later
            if dout = C_DATA(i) then
                report "read " & integer'image(i) & " OK: " & integer'image(to_integer(unsigned(dout)));
            else
                report "read " & integer'image(i) & " MISMATCH: got " & integer'image(to_integer(unsigned(dout)))
                     & ", expected " & integer'image(to_integer(unsigned(C_DATA(i)))) severity error;
                errors <= errors + 1;
            end if;
        end loop;

        -- all four words are out, so empty must come back (after the read pointer crosses to the write side and back)
        for i in 1 to 5 loop
            wait until rising_edge(rd_clk);
        end loop;
        if empty /= '1' then
            report "empty did not return high after reading everything" severity error;
            errors <= errors + 1;
        end if;
        rd_done <= true;
        wait;
    end process process_read;

    process_stimulus : process
    begin
        wait until rd_done for 20 us; -- watchdog: a stuck FIFO fails here instead of running forever
        wait for 100 ns;              -- let the errors signal settle
        if not rd_done then
            report "SMOKE TEST FAILED: timeout, the reads never finished" severity error;
        elsif errors = 0 then
            report "SMOKE TEST PASSED";
        else
            report "SMOKE TEST FAILED: " & integer'image(errors) & " error(s)" severity error;
        end if;

        assert false
            report "SIM DONE"
            severity failure;
    end process process_stimulus;

    process_wr_clk : process
    begin
        wr_clk <= '0';
        wait for CLK_PERIOD1/2;
        wr_clk <= '1';
        wait for CLK_PERIOD1/2;
    end process process_wr_clk;

    process_rd_clk : process
    begin
        rd_clk <= '0';
        wait for CLK_PERIOD2/2;
        rd_clk <= '1';
        wait for CLK_PERIOD2/2;
    end process process_rd_clk;

  my_fifo : entity work.fifo_generator_0
    port map
    (
      wr_clk    => wr_clk,
      rd_clk    => rd_clk,
      din       => din,
      wr_en     => wr_en,
      rd_en     => rd_en,
      dout      => dout,
      full      => full,
      empty     => empty,
      wr_ack    => wr_ack,
      overflow  => overflow,
      valid     => valid,
      underflow => underflow
    );

end Behavioral;
