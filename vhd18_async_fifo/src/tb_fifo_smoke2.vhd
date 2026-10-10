-- Smoke test 2: overflow and underflow.
-- Writes more words than the FIFO holds, then reads more words than it accepted.
-- Counts the handshaking flags and checks which words come out.
library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;

entity tb_fifo_smoke2 is
  --  Port ( );
end tb_fifo_smoke2;

architecture Behavioral of tb_fifo_smoke2 is

  signal wr_clk : std_logic := '0';
  signal rd_clk : std_logic := '0';
  signal din    : std_logic_vector(7 downto 0) := (others => '0');
  signal wr_en  : std_logic := '0';
  signal rd_en  : std_logic := '0';
  signal dout   : std_logic_vector(7 downto 0);
  signal full   : std_logic;
  signal empty  : std_logic;

  signal wr_ack    : std_logic; -- wr_clk: the write was accepted
  signal overflow  : std_logic; -- wr_clk: wr_en while full, the write was rejected
  signal valid     : std_logic; -- rd_clk: dout holds valid data
  signal underflow : std_logic; -- rd_clk: rd_en while empty

  constant CLK_PERIOD1 : time := 10 ns;
  constant CLK_PERIOD2 : time := 27 ns;

  constant C_DEPTH : integer := 15; -- usable depth (Summary tab)
  constant C_N_WR  : integer := 20; -- write attempts, more than C_DEPTH
  constant C_N_RD  : integer := 20; -- read attempts, more than the number of words that were accepted

  type t_rx is array (0 to 31) of std_logic_vector(7 downto 0);

  signal burst_wr_done : boolean := false;
  signal burst_rd_done : boolean := false;

  -- counted by the monitors, each signal has a single driver
  signal ack_cnt   : integer := 0;       -- process_mon_wr
  signal ovf_cnt   : integer := 0;       -- process_mon_wr
  signal full_seen : boolean := false;   -- process_mon_wr
  signal valid_cnt : integer := 0;       -- process_mon_rd
  signal udf_cnt   : integer := 0;       -- process_mon_rd
  signal rx_data   : t_rx := (others => (others => '0')); -- process_mon_rd, words seen with valid = '1'

begin

    -- Overflow: write more words than the FIFO holds, back to back, with no reads
    process_write : process
    begin
        -- the model has no reset pin, give it time to finish its internal power-on reset
        for i in 1 to 50 loop
            wait until rising_edge(wr_clk);
        end loop;
        assert full = '0' report "full is not low after start-up" severity error;

        for i in 0 to C_N_WR - 1 loop
            wait until rising_edge(wr_clk);
            din   <= std_logic_vector(to_unsigned(16#10# + i, 8));
            wr_en <= '1';
        end loop;
        wait until rising_edge(wr_clk); -- the FIFO samples the last word on this edge
        wr_en <= '0';
        burst_wr_done <= true;
        wait;
    end process process_write;

    -- Underflow: once the burst is in, read more words than were accepted, back to back
    process_read : process
    begin
        wait until burst_wr_done;
        wait until rising_edge(rd_clk) and empty = '0';
        for i in 0 to C_N_RD - 1 loop
            rd_en <= '1';
            wait until rising_edge(rd_clk);
        end loop;
        rd_en <= '0';
        for i in 1 to 5 loop -- let the last valid and underflow flags show up
            wait until rising_edge(rd_clk);
        end loop;
        burst_rd_done <= true;
        wait;
    end process process_read;

    -- Monitors: count the flags and record the words, one sample per clock edge
    process_mon_wr : process (wr_clk)
    begin
        if rising_edge(wr_clk) then
            if wr_ack = '1' then
                ack_cnt <= ack_cnt + 1;
            end if;
            if overflow = '1' then
                ovf_cnt <= ovf_cnt + 1;
            end if;
            if full = '1' then
                full_seen <= true;
            end if;
        end if;
    end process process_mon_wr;

    process_mon_rd : process (rd_clk)
    begin
        if rising_edge(rd_clk) then
            if valid = '1' then
                if valid_cnt < 32 then
                    rx_data(valid_cnt) <= dout;
                end if;
                valid_cnt <= valid_cnt + 1;
            end if;
            if underflow = '1' then
                udf_cnt <= udf_cnt + 1;
            end if;
        end if;
    end process process_mon_rd;

    process_main : process
        variable errors : integer := 0;
    begin
        wait until burst_rd_done for 50 us; -- watchdog: a stuck FIFO fails here instead of running forever
        wait for 100 ns;                    -- let the counters settle
        report "accepted writes (wr_ack) = " & integer'image(ack_cnt)
             & ", overflow = " & integer'image(ovf_cnt)
             & ", valid reads = " & integer'image(valid_cnt)
             & ", underflow = " & integer'image(udf_cnt)
             & ", full seen = " & boolean'image(full_seen);

        if not burst_rd_done then
            report "SMOKE TEST 2 FAILED: timeout" severity error;
            errors := errors + 1;
        end if;
        -- expectations: the first C_DEPTH writes are accepted and the rest are rejected,
        -- and the same goes for the reads. These are predictions for the IP, not its documented behavior.
        if ack_cnt /= C_DEPTH then
            report "expected " & integer'image(C_DEPTH) & " accepted writes" severity error;
            errors := errors + 1;
        end if;
        if ovf_cnt /= C_N_WR - C_DEPTH then
            report "expected " & integer'image(C_N_WR - C_DEPTH) & " overflow pulses" severity error;
            errors := errors + 1;
        end if;
        if not full_seen then
            report "full never went high" severity error;
            errors := errors + 1;
        end if;
        if valid_cnt /= C_DEPTH then
            report "expected " & integer'image(C_DEPTH) & " valid reads" severity error;
            errors := errors + 1;
        end if;
        if udf_cnt /= C_N_RD - C_DEPTH then
            report "expected " & integer'image(C_N_RD - C_DEPTH) & " underflow pulses" severity error;
            errors := errors + 1;
        end if;
        -- the words that came out must be the first C_DEPTH written, in order
        for i in 0 to C_DEPTH - 1 loop
            if rx_data(i) /= std_logic_vector(to_unsigned(16#10# + i, 8)) then
                report "word " & integer'image(i) & ": got " & integer'image(to_integer(unsigned(rx_data(i))))
                     & ", expected " & integer'image(16#10# + i) severity error;
                errors := errors + 1;
            end if;
        end loop;
        if empty /= '1' then
            report "empty is not high after reading everything" severity error;
            errors := errors + 1;
        end if;

        if errors = 0 then
            report "SMOKE TEST 2 PASSED";
        else
            report "SMOKE TEST 2 FAILED: " & integer'image(errors) & " error(s)" severity error;
        end if;

        assert false
            report "SIM DONE"
            severity failure;
    end process process_main;

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
