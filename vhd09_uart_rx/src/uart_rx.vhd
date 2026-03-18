library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity uart_rx is
generic(
    CLK_FREQ  : integer := 100_000_000;
    BAUD_RATE : integer := 115_200
);
port(
    clk       : in  std_logic;
    rx_in     : in  std_logic;
    data_out  : out std_logic_vector(7 downto 0);
    read_done : out std_logic
);
end uart_rx;

architecture Behavioral of uart_rx is
  type t_state is (s_IDLE, s_START, s_DATA, s_STOP);
  signal state : t_state := s_IDLE;

  constant BAUD_TICKS : integer := CLK_FREQ / BAUD_RATE; 
  constant MID_TICKS  : integer := BAUD_TICKS / 2;

  signal timer   : integer range 0 to BAUD_TICKS := 0;
  signal bit_cnt : integer range 0 to 7 := 0;
  signal shreg   : std_logic_vector(7 downto 0) := (others => '0');

  signal read_done_r : std_logic := '0';
begin

  data_out  <= shreg;
  read_done <= read_done_r;

  process(clk)
  begin
    if rising_edge(clk) then

      case state is

        when s_IDLE =>
          read_done_r <= '0';
          timer       <= 0;
          bit_cnt     <= 0;
          
          if rx_in = '0' then                   -- start bit detected (line went low)
            state <= s_START;
          end if;

        when s_START =>
          -- wait half-bit to sample middle of start bit (debounce)
          if (timer = MID_TICKS-1) then
            timer <= 0;
            state <= s_DATA;
          else
            timer <= timer + 1;
          end if;

        when s_DATA =>
          if (timer = BAUD_TICKS-1) then
                -- sample data bit at bit boundary
                shreg <= rx_in & shreg(7 downto 1);   --d0 first d7 last
                timer <= 0;

                if (bit_cnt = 7) then
                  bit_cnt     <= 0;
                  state       <= s_STOP;
                else
                  bit_cnt <= bit_cnt + 1;
                end if;
            
          else
                timer <= timer + 1;
          end if;

        when s_STOP =>
          if (timer = BAUD_TICKS-1) then
            timer       <= 0;
            read_done_r <= '1';
            state       <= s_IDLE;
          else
            timer <= timer + 1;
          end if;

      end case;
    end if;
  end process;

end Behavioral;
