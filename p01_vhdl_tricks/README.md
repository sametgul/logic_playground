# VHDL Notes: Behaviors, Pitfalls, and Useful Tricks

A compact field guide to VHDL semantics and safe coding patterns.


# VHDL Notes: Behaviors, Pitfalls, and Useful Tricks

A compact field guide to VHDL semantics and safe coding patterns.

## Process Semantics (the essentials)

* Inside **one process**, statements execute **sequentially** (top to bottom).
* **Different processes** run **concurrently**.
* **Signal** assignments update **after** the process suspends (end of delta cycle or clock edge). Multiple writes to the **same signal** inside one process resolve to the **last** one.
* VHDL is **case-insensitive**.

### Signals vs Variables (why your update “did nothing”)

* **Signals** (`<=`) read the *old* value until the process suspends.
* **Variables** (`:=`) update immediately and are visible to subsequent lines in the same process.

```vhdl
process(clk) is
  variable tmp : unsigned(7 downto 0);
begin
  if rising_edge(clk) then
    tmp := unsigned(b) + unsigned(c); -- immediate
    a   <= std_logic_vector(tmp);     -- scheduled for after edge
  end if;
end process;
```

### “Last assignment wins” (inside one process)

```vhdl
process(clk) begin
  if rising_edge(clk) then
    if sel = '0' then
      a <= b + c;
    else
      a <= b - c;
    end if;

    -- This line overrides the two above, still using OLD 'a' on RHS
    a <= a + b + c;

    if op = '1' then
      a <= x"03";  -- This is the final value assigned this cycle
    end if;
  end if;
end process;
```


## Common Combinational Pitfalls

When writing a **combinational process**, watch out for:

1. **Sensitivity list**

   * All signals that are read must appear in the sensitivity list.
   * Otherwise: simulation mismatches.

2. **Missing branches**
Always drive every output on every path.

   * Every `if` should have an `else`, every `case` should have a `when others`.
   * Otherwise: unintended **latch inference**.

3. **Read + write of same signal**

   * Writing and reading the same signal in a combinational process may cause **feedback loops**.

### Example 1: Unintended Latch

```vhdl
PROCESS3 : process (sel, b, c)
begin
  if (sel = '0') then
    a <= b + c;
  end if;
end process PROCESS3;
```

Here, if `sel = '1'`, signal `a` keeps its previous value. Because this is not sequential logic, the synthesizer infers a **latch**. Vivado synthesizes it but gives a warning.

```vhdl
p_comb : process(all) is -- VHDL-2008
begin
  a <= (others => '0');                -- default
  if sel = '0' then
    a <= b + c;
  end if;                              -- no latch because default covers else
end process;
```

### Example 2: Combinational Feedback

```vhdl
PROCESS4 : process (sel, a, b, c)
begin
  if (sel = '0') then
    a <= a + b + c;
  else
    a <= a - b - c;
  end if;
end process PROCESS4;
```

Here, `a` is both read and written inside the same process. This creates a **combinational feedback loop**. Vivado synthesizes it without warnings, but it may cause oscillation or unstable behavior. This can even lead to damage the fpga chip.

## Hierarchy Optimization in Vivado

Vivado has options like **rebuilt** and **none** for how it handles module hierarchy during synthesis:

* `rebuilt`: optimizer flattens and merges logic, removing unnecessary hierarchy. Your design may appear as one flat block.
* `none`: keeps submodules and hierarchy intact.

![merge](docs/merge_structures.png)

## Reset Strategy

* Xilinx recommends **synchronous, active-high reset**. This aligns with FPGA internal logic (active-high reset and clock-enable).
* Still, asynchronous reset is sometimes necessary.
* One trick is to use a generic like `rst_type : string := "ASYNC"` to switch between sync/async reset implementations.

### Example

```vhdl
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity top is
  generic (
    rst_type : string := "ASYNC"
  );
  port (
    clk : in std_logic;
    rst : in std_logic;
    a   : in std_logic;
    b   : in std_logic;
    c   : in std_logic;
    y   : out std_logic
  );
end top;

architecture Behavioral of top is
  -- Signal initialized to '1'. In SRAM-based FPGAs, FFs power up initialized.
  -- In ASICs or flash-based FPGAs, explicit reset is required.
  signal y_int : std_logic := '1';
begin

  -- Synchronous Reset
  G_SYNC : if rst_type = "SYNC" generate
    process (clk)
    begin
      if rising_edge(clk) then
        if (rst = '1') then
          y_int <= '1';
        else
          y_int <= (a and b and (not c)) or
                   ((not a) and b and c) or
                   ((not a) and (not b) and (not c));
        end if;
      end if;
    end process;
  end generate;

  -- Asynchronous Reset
  G_ASYNC : if rst_type = "ASYNC" generate
    process (clk, rst)
    begin
      if (rst = '1') then
        y_int <= '1';
      elsif rising_edge(clk) then
        y_int <= (a and b and (not c)) or
                 ((not a) and b and c) or
                 ((not a) and (not b) and (not c));
      end if;
    end process;
  end generate;

  y <= y_int;
end Behavioral;
```

## Clock-domain crossing (CDC) quick recipes

I will cover these in the future projects in detail.

* **Single-bit control** from async/other domain → **2-FF synchronizer** (or 3-FF for extra MTBF).
* **Pulses** → convert to **toggle** in source domain; detect edge in dest domain.
* **Multi-bit data** → **dual-clock FIFO**, or Gray-coded counters with dual-port RAM.
* **Handshakes** → ready/valid or req/ack with proper synchronizers on each crossing bit.


## Timing Closure Trick

When struggling with timing violations:

* Add 2–4 input registers near the top level; enable **retiming** in synthesis  (`Settings → Synthesis → Retiming`). Tools can legally move these through logic to balance paths, and may improving timing.
* Pipeline arithmetic (DSP48s love registered inputs and mids).
* Constrain clocks properly; avoid false/multicycle unless you fully understand them.

![register](docs/replace_registers.png)

## References

* [VHDL ile FPGA PROGRAMLAMA](https://www.udemy.com/course/vhdl-ile-fpga-programlama-temel-seviye/)