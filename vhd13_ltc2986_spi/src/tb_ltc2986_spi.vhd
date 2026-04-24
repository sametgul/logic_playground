library IEEE;
use IEEE.STD_LOGIC_1164.all;

--------------------------------------------------------------------------------
-- Testbench for ltc2986_spi.
--
-- Simulates three transactions:
--   1. Write 1 byte: start conversion on channel 1
--        addr=0x0000, wr_data=0x81000000 (cmd 0x80 | ch1)
--   2. Read 1 byte: poll status register
--        addr=0x0000 — check rd_data[30] ('1' = conversion done)
--   3. Read 4 bytes: fetch channel-1 temperature result
--        addr=0x0010 — upper byte = faults, lower 24 bits = temp (1/1024 degC)
--
-- A simple LTC2986 responder is included: it drives MISO for the read
-- transactions so the received values can be inspected in the waveform.
--------------------------------------------------------------------------------

entity tb_ltc2986_spi is
end tb_ltc2986_spi;

architecture Behavioral of tb_ltc2986_spi is

  -- DUT generics: 12 MHz system clock, 1 MHz SCK (easier to simulate)
  constant CLK_FREQ       : integer := 12_000_000;
  constant SCLK_FREQ      : integer := 1_000_000;
  constant HALF_PER       : integer := CLK_FREQ / (SCLK_FREQ * 2); -- 6 cycles
  constant CS_SETUP_TICKS : integer := 2;
  constant CS_IDLE_TICKS  : integer := 2;
  constant CLK_PERIOD     : time    := 1_000_000_000 ns / CLK_FREQ; -- ~83 ns

  -- DUT ports
  signal clk       : std_logic := '0';
  signal start     : std_logic := '0';
  signal rd_wr_n   : std_logic := '0';
  signal addr      : std_logic_vector(15 downto 0) := (others => '0');
  signal n_bytes   : natural range 1 to 4 := 1;
  signal wr_data   : std_logic_vector(31 downto 0) := (others => '0');
  signal rd_data   : std_logic_vector(31 downto 0);
  signal busy      : std_logic;
  signal done      : std_logic;
  signal ltc_int_n : std_logic := '1';
  signal conv_done : std_logic;
  signal sclk      : std_logic;
  signal mosi      : std_logic;
  signal miso      : std_logic := '0';
  signal cs_n      : std_logic;

  -- Simulated MISO response for read transactions (driven by responder process)
  signal miso_byte : std_logic_vector(7 downto 0) := (others => '0');
  signal miso_bit  : integer range 0 to 7 := 7;

begin

  clk <= not clk after CLK_PERIOD / 2;

  DUT : entity work.ltc2986_spi
    generic map (
      CLK_FREQ       => CLK_FREQ,
      SCLK_FREQ      => SCLK_FREQ,
      CS_SETUP_TICKS => CS_SETUP_TICKS,
      CS_IDLE_TICKS  => CS_IDLE_TICKS
    )
    port map (
      clk       => clk,
      start     => start,
      rd_wr_n   => rd_wr_n,
      addr      => addr,
      n_bytes   => n_bytes,
      wr_data   => wr_data,
      rd_data   => rd_data,
      busy      => busy,
      done      => done,
      ltc_int_n => ltc_int_n,
      conv_done => conv_done,
      sclk      => sclk,
      mosi      => mosi,
      miso      => miso,
      cs_n      => cs_n
    );

  -- ── Stimulus ────────────────────────────────────────────────────────────────
  p_STIM : process
    procedure send_pulse(signal s : out std_logic) is
    begin
      s <= '1';
      wait until rising_edge(clk);
      s <= '0';
    end procedure;

    procedure wait_done is
    begin
      wait until rising_edge(clk) and done = '1';
      wait until rising_edge(clk); -- one extra cycle for rd_data to settle
    end procedure;

  begin
    wait for CLK_PERIOD * 5;

    -- ── Transaction 1: Write — start conversion on channel 1 ─────────────────
    -- Write 0x81 to address 0x0000  (command: 0x80 | channel_1)
    rd_wr_n <= '0';
    addr    <= x"0000";
    n_bytes <= 1;
    wr_data <= x"81000000"; -- 0x81 left-justified in upper byte
    send_pulse(start);
    wait_done;

    -- Simulate LTC2986 asserting /INTERRUPT low (conversion started)
    ltc_int_n <= '0';
    wait for CLK_PERIOD * 20;

    -- ── Transaction 2: Read — poll status register ────────────────────────────
    -- Read 1 byte from address 0x0000; expect 0x40 (bit 6 set = conversion done)
    rd_wr_n   <= '1';
    addr      <= x"0000";
    n_bytes   <= 1;
    -- miso_byte drives 0x40 during the data phase (see responder below)
    miso_byte <= x"40";
    send_pulse(start);
    wait_done;
    -- rd_data[31:24] should be 0x40

    -- Simulate LTC2986 releasing /INTERRUPT (conversion done)
    ltc_int_n <= '1';
    wait for CLK_PERIOD * 5;
    -- conv_done should pulse here

    -- ── Transaction 3: Read — fetch channel-1 temperature result ─────────────
    -- Read 4 bytes from address 0x0010
    -- Simulated result: 0x00_190000 = 0 faults, temp = 0x190000/1024 = 25.0 degC
    rd_wr_n   <= '1';
    addr      <= x"0010";
    n_bytes   <= 4;
    miso_byte <= x"00"; -- first byte (fault flags); responder will cycle through bytes
    send_pulse(start);
    wait_done;
    -- rd_data[31:0] should reflect the 4 bytes received via MISO

    wait for CLK_PERIOD * 20;
    report "Simulation complete." severity note;
    wait;
  end process;

  -- ── MISO Responder ───────────────────────────────────────────────────────────
  -- Drives MISO on the falling edge of SCK (LTC2986 updates SDO 225 ns after
  -- SCK falls; for simulation, we drive immediately on the falling edge).
  -- For simplicity, this responder shifts out the same miso_byte for every
  -- data byte in a read transaction.  The 3 header bytes (instruction + address)
  -- are ignored (MISO=0 during that time).
  p_RESPONDER : process
    variable bit_idx : integer := 7;
    variable byte_n  : integer := 0;
  begin
    miso    <= '0';
    miso_bit <= 7;
    wait until cs_n = '0';

    -- Count which byte we are in (0=instr, 1=addr_hi, 2=addr_lo, 3..=data)
    byte_n  := 0;
    bit_idx := 7;

    while cs_n = '0' loop
      wait until falling_edge(sclk) or cs_n = '1';
      if cs_n = '1' then exit; end if;

      if byte_n >= 3 then
        -- Data phase: drive MISO
        miso <= miso_byte(bit_idx);
      else
        miso <= '0';
      end if;

      if bit_idx = 0 then
        bit_idx := 7;
        byte_n  := byte_n + 1;
      else
        bit_idx := bit_idx - 1;
      end if;
    end loop;

    miso <= '0';
  end process;

end Behavioral;
