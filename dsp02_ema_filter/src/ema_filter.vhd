library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;

-- Direct VHDL translation of dsp02_ema_filter/models/ema_fixed.py: see that
-- file (and required_guard_bits) for why the accumulator needs GUARD_BITS
-- of extra fractional precision beyond the native input/output word.
entity ema_filter is
	generic (
		INT_BITS   : integer := 3;  -- Qm.f integer bits, including the sign bit
		FRAC_BITS  : integer := 21; -- native fractional bits (input/output word)
		GUARD_BITS : integer := 20  -- extra accumulator fractional bits
	);
	port (
		clk : in std_logic;
		rst : in std_logic; -- synchronous, clears the accumulator and output valid

		-- unsigned Q0.(FRAC_BITS+GUARD_BITS), i.e. alpha's own code already at the accumulator's fractional width
		alpha_i : in std_logic_vector(FRAC_BITS + GUARD_BITS - 1 downto 0);

		s_axis_tvalid : in std_logic;
		s_axis_tready : out std_logic;
		s_axis_tdata  : in std_logic_vector(INT_BITS + FRAC_BITS - 1 downto 0);

		m_axis_tvalid : out std_logic;
		m_axis_tready : in std_logic;
		m_axis_tdata  : out std_logic_vector(INT_BITS + FRAC_BITS - 1 downto 0)
	);
end ema_filter;

architecture behavioral of ema_filter is

	constant DATA_WIDTH    : integer := INT_BITS + FRAC_BITS;
	constant ACC_FRAC_BITS : integer := FRAC_BITS + GUARD_BITS;
	constant ACC_WIDTH     : integer := INT_BITS + ACC_FRAC_BITS;
	-- diff (ACC_WIDTH bits) * alpha_s (ACC_FRAC_BITS+1 bits), per signed "*" result width rules
	constant PRODUCT_WIDTH : integer := ACC_WIDTH + ACC_FRAC_BITS + 1;

	signal y_acc_r : signed(ACC_WIDTH - 1 downto 0) := (others => '0');
	signal out_valid_r : std_logic := '0';
	signal out_data_r  : signed(DATA_WIDTH - 1 downto 0) := (others => '0');

	-- Clamp v to the representable range of target_width bits, then narrow to it.
	-- Needed anywhere a value might not actually fit (overflow on add, or
	-- rounding pushing a value already at the rail past it) - unlike resize(),
	-- this never silently wraps.
	function saturate_resize(v : signed; target_width : natural) return signed is
		variable max_t : signed(target_width - 1 downto 0) := '0' & (target_width - 2 downto 0 => '1');
		variable min_t : signed(target_width - 1 downto 0) := '1' & (target_width - 2 downto 0 => '0');
	begin
		if v > resize(max_t, v'length) then
			return max_t;
		elsif v < resize(min_t, v'length) then
			return min_t;
		else
			return resize(v, target_width);
		end if;
	end function;

	function saturate_add(a, b : signed) return signed is
	begin
		return saturate_resize(resize(a, a'length + 1) + resize(b, a'length + 1), a'length);
	end function;

	-- Round-to-nearest right shift (add half the dropped weight, then shift).
	-- Safe from overflow by construction: v_ext has one more bit of headroom
	-- than v ever uses, and shifting right only shrinks magnitude further.
	function round_shift(v : signed; shift : natural) return signed is
		variable v_ext : signed(v'length downto 0);
		variable half  : signed(v'length downto 0);
	begin
		if shift = 0 then
			return v;
		end if;
		v_ext := resize(v, v'length + 1);
		half  := shift_left(to_signed(1, v'length + 1), shift - 1);
		return resize(shift_right(v_ext + half, shift), v'length);
	end function;

begin

	s_axis_tready <= (not out_valid_r) or m_axis_tready;
	m_axis_tvalid <= out_valid_r;
	m_axis_tdata  <= std_logic_vector(out_data_r);

	p_SEQUENTIAL : process (clk)
		variable x_aligned : signed(ACC_WIDTH - 1 downto 0);
		variable diff       : signed(ACC_WIDTH - 1 downto 0);
		variable alpha_s    : signed(ACC_FRAC_BITS downto 0);
		variable product    : signed(PRODUCT_WIDTH - 1 downto 0);
		variable increment  : signed(ACC_WIDTH - 1 downto 0);
		variable y_acc_next : signed(ACC_WIDTH - 1 downto 0);
	begin
		if rising_edge(clk) then
			if rst = '1' then
				y_acc_r     <= (others => '0');
				out_valid_r <= '0';
				out_data_r  <= (others => '0');
			elsif s_axis_tvalid = '1' and s_axis_tready = '1' then
				x_aligned := shift_left(resize(signed(s_axis_tdata), ACC_WIDTH), GUARD_BITS);
				diff := x_aligned - y_acc_r;

				alpha_s := signed('0' & alpha_i);
				product := diff * alpha_s; -- fractional bits: ACC_FRAC_BITS (diff) + ACC_FRAC_BITS (alpha)

				increment := resize(round_shift(product, ACC_FRAC_BITS), ACC_WIDTH);
				y_acc_next := saturate_add(y_acc_r, increment);

				y_acc_r     <= y_acc_next;
				out_data_r  <= saturate_resize(round_shift(y_acc_next, GUARD_BITS), DATA_WIDTH);
				out_valid_r <= '1';
			elsif m_axis_tready = '1' then
				out_valid_r <= '0';
			end if;
		end if;
	end process p_SEQUENTIAL;

end behavioral;
