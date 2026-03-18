# BRAM Usage — Single-Port Block RAM

This module implements a **single-port synchronous RAM** (Block RAM inference) in VHDL.
It supports **READ_FIRST** and **WRITE_FIRST** modes and configurable read latency (**1-CLK** or **2-CLK**).

---

## Source Files

| File | Description |
|------|-------------|
| `src/spbram.vhd` | Single-port BRAM RTL — parametric read mode and latency |
| `src/tb_spbram.vhd` | Testbench — exercises all four mode/latency combinations |
| `src/uart_bram.vhd` | Top level — receive 3 bytes over UART, store in BRAM, echo back in reverse |

---

## Generics

> Generic string values are **case-sensitive**. Use exactly `"READ_FIRST"` / `"WRITE_FIRST"` and `"1_CLK"` / `"2_CLK"`. Note that `read_type` is intentionally lowercase to match common Xilinx BRAM inference style — all other generics follow the usual UPPERCASE convention.

| Name        | Type    | Default        | Description                                      |
|-------------|---------|----------------|--------------------------------------------------|
| `WIDTH`     | integer | `8`            | Data bus width (bits per word)                   |
| `ADDR_BITS` | integer | `14`           | Address width — depth = 2^ADDR_BITS              |
| `read_type` | string  | `"READ_FIRST"` | Read behavior: `"READ_FIRST"` or `"WRITE_FIRST"` |
| `LAT`       | string  | `"2_CLK"`      | Read latency: `"1_CLK"` or `"2_CLK"`             |

---

## Read Latency

### 1-CLK

`dout_o` updates **one clock** after address changes.

```
clk:   ┌─┐   ┌─┐   ┌─┐
addr:  AAAAA BBBBB CCCCC
dout:  ----- AAA   BBB
```

### 2-CLK

Additional output register — **two clocks** of latency. Helps timing closure at high frequencies.

```
clk:   ┌─┐   ┌─┐   ┌─┐   ┌─┐
addr:  AAAAA BBBBB CCCCC
dout:  ----- ----- AAA   BBB
```

---

## Read/Write Modes

**READ_FIRST** — on a write to the addressed location, `dout_o` shows the **old data** in that cycle. The updated value appears on the next cycle.

**WRITE_FIRST** — on a write, `dout_o` immediately reflects the **new write data** in the same cycle.

### The WRITE_FIRST + 2_CLK caveat

When `LAT="2_CLK"` and `read_type="WRITE_FIRST"` are combined, there is a conflict: the pipeline introduces a 2-cycle delay, but WRITE_FIRST requires the new data to appear immediately. These two requirements cannot both be satisfied at once.

The current implementation resolves this by **bypassing the pipeline on write cycles**:

```vhdl
if we_i = '1' then
    ram(to_integer(unsigned(addr_i))) <= din_i;
    dout_o <= din_i;   -- bypass: drives output directly, skipping the 2-cycle pipeline
end if;
```

The consequence is that on write cycles the effective latency drops to 0, while on read cycles it remains 2. This inconsistency is usually harmless in practice — most designs either write or read in a given cycle, not both.

**If you need strict 2-cycle latency on every cycle without exception**, remove the bypass line:

```vhdl
-- Remove this line to get strict 2-CLK latency on all cycles:
dout_o <= din_i;   -- <-- delete this
```

After removing it, WRITE_FIRST behavior is no longer guaranteed during the pipeline drain cycles — the new data will appear 2 cycles late on write cycles. Whether this matters depends on your design.

---

## Inference & Device Notes

The RAM is declared as a VHDL array with a synthesis attribute to guide Vivado toward BRAM:

```vhdl
attribute ram_style : string;
attribute ram_style of ram : signal is "block";
```

Very small depths may still infer **LUTRAM** if the tool decides it is more efficient. To make the code portable across vendors, remove these attribute lines — the synthesis tool will then decide the implementation automatically.

Xilinx BRAM mapping:

- `LAT="1_CLK"` → `DOA_REG = 0` (unregistered output)
- `LAT="2_CLK"` → `DOA_REG = 1` (registered output)

This design targets **single-port** memories only. For true dual-port (simultaneous read + write on separate ports), a different architecture is needed.

**Power-up behavior:** the RTL initializes the array to zeros in simulation. On hardware, power-up contents are undefined unless an init file is provided — not included here.

---

## Minimal Usage

```vhdl
u_bram : entity work.spbram
  generic map (
    WIDTH      => 16,
    ADDR_BITS  => 10,
    read_type  => "WRITE_FIRST",
    LAT        => "1_CLK"
  )
  port map (
    clk    => clk,
    we_i   => we,
    addr_i => addr,
    din_i  => din,
    dout_o => dout
  );
```

---

## Top Level — UART + BRAM Echo (`uart_bram.vhd`)

This top level ties together the UART RX, UART TX, and BRAM cores into a complete system. It demonstrates the key challenge of working with registered BRAM outputs — specifically that **you must wait one cycle after changing the address before reading `dout_o`**.

**Behavior:**

1. Receive 3 bytes over UART and store them into BRAM at addresses 0, 1, 2
2. Read them back in **reverse order** (addr 2 → 1 → 0) and echo over UART TX
3. Return to idle, ready for the next 3-byte sequence

```
Receive:  AA → addr 0 | BB → addr 1 | CC → addr 2
Echo TX:  CC           BB             AA
```

LED behavior:

- `"00"` — power-up
- `"01"` — receiving in progress
- `"10"` — echo complete, returned to idle

**The BRAM read timing problem and how it is solved**

After changing `addr_i`, `dout_o` is not valid until the next rising edge (`LAT="1_CLK"`). Reading `dout_o` in the same cycle as the address change captures stale data — this was the root cause of getting `BB BB AA` instead of `CC BB AA`.

The solution is a split state pattern for each read:

```
xSETADDR: change addr_i → transition to xREAD
xREAD:    dout_o is now valid → capture into datain, assert start_tx
```

For STATE5 and STATE6, the `xSETADDR` state also doubles as the `tx_done` wait — two jobs in one state, keeping the FSM compact.

> **Rule of thumb:** always insert at least one cycle between changing a synchronous RAM address and reading the output. The same principle applies to any pipelined memory interface.

---

## Vivado Synthesis Notes

With `read_type = "READ_FIRST"`, Vivado reports the BRAM property accordingly:

![read_first property](docs/readfirst.png)

With `LAT = "2_CLK"`, Vivado registers the output (`DOA_REG = 1`); with `"1_CLK"` it would be `DOA_REG = 0`:

![2_clk latency](docs/2clk.png)

---

## Testbench

The testbench exercises the four mode/latency combinations and verifies read-back timing. Results:

![tb](docs/testbench.png)

---

## References

1. [VHDL ile FPGA PROGRAMLAMA](https://www.udemy.com/course/vhdl-ile-fpga-programlama-temel-seviye/)

---
⬅️  [MAIN PAGE](../README.md)