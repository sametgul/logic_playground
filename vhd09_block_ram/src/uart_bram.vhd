library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;

entity uart_bram is
  generic (
    CLK_FREQ  : integer := 12_000_000;
    BAUD_RATE : integer := 115_200;
    STOP_BIT  : integer := 1;

    WIDTH     : integer := 8;
    DEPTH     : integer := 10;
    read_type : string  := "WRITE_FIRST";
    LAT       : string  := "1_CLK"
  );
  port (
    clk     : in  std_logic;
    uart_rx : in  std_logic;
    uart_tx : out std_logic;
    led     : out std_logic_vector(1 downto 0)
  );
end uart_bram;

architecture Behavioral of uart_bram is

  -- RX signals
  signal rx_data : std_logic_vector(7 downto 0);
  signal rx_done : std_logic;
  signal r_led   : std_logic_vector(1 downto 0) := "00";

  -- TX signals
  signal start_tx     : std_logic                    := '0';
  signal datain       : std_logic_vector(7 downto 0) := (others => '0');
  signal tx_done      : std_logic;
  signal tx_done_prev : std_logic                    := '0';

  -- BRAM signals
  signal we_i   : std_logic                             := '0';
  signal addr_i : integer range 0 to (2 ** DEPTH - 1)   := 0;
  signal din_i  : std_logic_vector(WIDTH - 1 downto 0)  := (others => '0');
  signal dout_o : std_logic_vector(WIDTH - 1 downto 0);

  -- BRAM LAT="1_CLK": after addr_i changes, dout_o is valid on the NEXT
  -- rising edge. Each xWAIT state gives BRAM one cycle to settle before
  -- datain is captured and start_tx is asserted.
  type t_state is (STATE1, STATE2, STATE3,
                   STATE4_SETADDR,
                   STATE4_READ,
                   STATE5_SETADDR,
                   STATE5_READ,
                   STATE6_SETADDR,
                   STATE6_READ);
  signal state : t_state := STATE1;

begin

  led <= r_led;

  pMAIN : process (clk)
  begin
    if rising_edge(clk) then

      start_tx     <= '0';
      tx_done_prev <= tx_done;
      we_i         <= '0';

      case state is

        -----------------------------------------------------------------------
        -- Receiving phase: store 3 incoming bytes into BRAM at addr 0, 1, 2
        -----------------------------------------------------------------------
        when STATE1 =>
          r_led  <= "01";
          addr_i <= 0;
          if (rx_done = '1') then
            din_i <= rx_data;
            we_i  <= '1';
            state <= STATE2;
          end if;

        when STATE2 =>
          if (rx_done = '1') then
            din_i  <= rx_data;
            addr_i <= 1;
            we_i   <= '1';
            state  <= STATE3;
          end if;

        when STATE3 =>
          if (rx_done = '1') then
            din_i  <= rx_data;
            addr_i <= 2;
            we_i   <= '1';
            state  <= STATE4_SETADDR;
          end if;

        -----------------------------------------------------------------------
        -- Sending phase: read back in reverse order (addr 2 → 1 → 0)
        -- xSETADDR: set address, wait one cycle for BRAM output to settle
        -- xREAD:    dout_o is valid, send it, wait for tx_done
        -----------------------------------------------------------------------
        when STATE4_SETADDR =>
          -- addr_i is already 2 from STATE3, but we_i just fired this cycle
          -- with WRITE_FIRST the output is valid immediately on write cycle
          -- however we still wait one clean read cycle to be safe
          addr_i <= 2;
          state  <= STATE4_READ;

        when STATE4_READ =>
          -- dout_o valid for addr 2 (CC)
          start_tx <= '1';
          datain   <= dout_o;
          addr_i   <= 1;              -- pre-set for next read
          state    <= STATE5_SETADDR;

        when STATE5_SETADDR =>
          -- wait for tx_done falling edge AND one BRAM settle cycle
          if (tx_done_prev = '1' and tx_done = '0') then
            state <= STATE5_READ;
          end if;

        when STATE5_READ =>
          -- dout_o valid for addr 1 (BB)
          start_tx <= '1';
          datain   <= dout_o;
          addr_i   <= 0;              -- pre-set for next read
          state    <= STATE6_SETADDR;

        when STATE6_SETADDR =>
          if (tx_done_prev = '1' and tx_done = '0') then
            state <= STATE6_READ;
          end if;

        when STATE6_READ =>
          -- dout_o valid for addr 0 (AA)
          start_tx <= '1';
          datain   <= dout_o;
          r_led    <= "10";
          state    <= STATE1;

      end case;
    end if;
  end process;

  inst_RX : entity work.uart_rx
    generic map(
      CLK_FREQ  => CLK_FREQ,
      BAUD_RATE => BAUD_RATE
    )
    port map(
      clk       => clk,
      rx_in     => uart_rx,
      data_out  => rx_data,
      read_done => rx_done
    );

  inst_TX : entity work.uart_tx
    generic map(
      CLK_FREQ  => CLK_FREQ,
      BAUD_RATE => BAUD_RATE,
      STOP_BIT  => STOP_BIT
    )
    port map(
      clk      => clk,
      start_tx => start_tx,
      data_in  => datain,
      tx_out   => uart_tx,
      tx_done  => tx_done
    );

  inst_BRAM : entity work.spbram
    generic map(
      WIDTH     => WIDTH,
      DEPTH     => DEPTH,
      read_type => read_type,
      LAT       => LAT
    )
    port map(
      clk    => clk,
      we_i   => we_i,
      addr_i => std_logic_vector(to_unsigned(addr_i, DEPTH)),
      din_i  => din_i,
      dout_o => dout_o
    );

end Behavioral;