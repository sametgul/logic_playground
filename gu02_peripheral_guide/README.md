# Peripheral Driver Development Guide

My methodology for writing FPGA peripheral drivers in VHDL — from reading the datasheet to verifying the analog output on the bench. Every step is illustrated with the **AD5628 (PmodDA4)** DAC driver as a worked example.

---

## Step 1 — Datasheet

Before writing any VHDL, extract the following or equivalent information from the datasheet. All information in the datasheet matters, but these items are most directly relevant to the code:

### Communication Protocol: SPI Mode
Identify CPOL and CPHA from the timing diagram — do not rely on the mode number alone, different vendors label them differently. Check:
- What level does SCLK idle at? (`CPOL`)
- Is data sampled on the first or second edge? (`CPHA`)

> **AD5628 example:** SCLK idles HIGH, data clocked in on the **falling** edge → Mode 2 (CPOL=1, CPHA=0).

### Frame Format
Identify the bit width, field positions, and MSB/LSB order. For different purposes, generally different frames exist for the chips. We can create some frames at this point according to our design. For example, configuration frame the control register of the related component.

> **AD5628 example:** 32-bit frame, MSB first.
> ```
>  [31:28]  [27:24]  [23:20]  [19:8]      [7:0]
>  PAD(4)   CMD(4)   ADDR(4)  DATA(12)    PAD(8)
> ```

### Timing Constraints
We need to check the timing diagram thoroughly, and later, we need to check with testbenches that our communication satisfies each requirement. Especially, look for setup/hold times around CS and SCLK, minimum CS high time between frames, and maximum SCLK frequency.

 **AD5628 example:**
 | Constraint | Spec |
 |------------|------|
 | t4 — CS fall to first SCLK edge | ≥ 13 ns |
 | t8 — CS high between frames | ≥ 15 ns |
 | Max SCLK | 50 MHz |

### Startup Sequence
Check whether the peripheral needs an initialisation process before normal operation. Some peripherals requires more complex initialization, read carefully.

> **AD5628 example:** Internal reference is disabled by default. Must send `0x08000001` (enable internal 2.5 V reference) before the first DAC write, otherwise output is 0 V regardless of what you write.

---

## Step 2 — Architecture

Sketch the module hierarchy as black boxes **on paper before writing a line of VHDL**.

```
top / stimulus
      │  start, dac_val
      ▼
  driver_wrapper          ← protocol state machine (init seq, frame assembly)
      │  start, mosi_dat
      ▼
    spi_core              ← bit-level SPI master (CPOL/CPHA, timing)
      │  sclk, mosi, miso, cs_n
      ▼
  [peripheral]
```

Define the **port contract** of each module before writing any logic. Decide:
- What triggers a transaction? (`start` pulse, or continuous?)
- How does the caller know when it is safe to send next? (`busy` flag or `done` pulse?)
- Where does frame assembly live? (in the wrapper, not the SPI core)

> **AD5628 example:**
> ```
> top_sawtooth.vhd
>  ├── clk_wiz_0          (Xilinx IP: 12 MHz → 100 MHz)
>  ├── sawtooth_gen.vhd   (fires start on every busy falling edge)
>  └── PmodDA4.vhd        (INIT_REF FSM + frame assembly)
>       └── spi_cs_timing.vhd  (universal SPI master, all 4 modes)
> ```

---

## Step 3 — Bottom-Up VHDL

Write the **innermost module first**, work outward. Each module must have a clean, tested port contract before the next layer is written. We need to write the related testbench for each structure before implementing the upper one.

**Order for a typical SPI peripheral:**
1. SPI core (`spi_cs_timing`) — timer, edge detect, shift register
2. Driver wrapper (`PmodDA4`) — frame assembly, init sequence FSM
3. Stimulus / waveform gen (`sawtooth_gen`) — generates the data stream
4. Top level (`top_sawtooth`) — wires everything, instantiates clock IP

**Key VHDL conventions** (see also [vhd00](../gu00_vhdl_template/README.md)):
- One entity per file, filename matches entity name
- All registers on `rising_edge(clk)`, no asynchronous resets unless required
- Generics for anything that might change: `CLK_FREQ`, `SCLK_FREQ`, `DATA_W`, `CPOL`, `CPHA`
- Default pulse signals to `'0'` at the top of the clocked process; assert for exactly one cycle

---

## Step 4 — Unit Simulation

Write a **testbench per module** with self-checking assertions. Do not move to the next layer until this one passes.

**Testbench essentials:**
- A behavioral slave model (shift register clocked on the correct SPI edge)
- Assertions that check the exact bit pattern received, not just "something arrived" if you can.
- An `assert FALSE report "SIM DONE" severity failure` at the end to stop the simulator cleanly

---

## Step 5 — Integration Simulation

Simulate the **full chain**: stimulus → driver wrapper → SPI pins. Verify:

- The init sequence fires exactly once on the first `start` pulse
- Frame content is correct for multiple transactions
- `busy` / `done` handshaking works correctly across the module boundary
- CS timing constraints are met (count the clock cycles between CS↓ and first SCLK edge)

> **AD5628 example:** `tb_PmodDA4.vhd` drives two back-to-back DAC writes and asserts both 32-bit frames — the INIT_REF frame (`0x08000001`) followed by the data frame (`0x030ABC00`).

**NOTE:** if simulation passes but hardware fails, suspect timing (setup/hold violations at the pin level) or voltage levels (logic family mismatches).

---

## Step 6 — Synthesis Check

Before going to hardware:

- **No latches** — every signal driven in a combinational process must have a default assignment or be covered in all branches
- **No undriven outputs** — check the synthesis warnings, not just errors
- **Timing constraints pass** — add a `create_clock` constraint for every clock; check the timing summary for negative slack
- **Clock domain crossings** — if any signal crosses clock domains, it needs a 2-FF synchroniser; Vivado will warn but not always catch functional CDC bugs

> **AD5628 example:** using Clock Wizard to generate 100 MHz from 12 MHz means `clk` and `clk100` are different domains. All logic is driven by `clk100`; the raw `clk` connects only to the Clock Wizard input. No CDC paths.

---

## Step 7 — Hardware Verification

### Logic Analyzer first
Capture the SPI bus and verify frame content matches simulation. We have not connected the component, just checking the spi wires of the FPGA at this point.

| Tool | What to check |
|------|--------------|
| Saleae / Analog Discovery | CS timing (t4, t8), frame bit pattern, SCLK frequency |
| Vivado ILA | Same, but triggered on internal signals |

### Oscilloscope second
Once frames are confirmed correct, verify the connected hardware behavior.

> **AD5628 example:** CH_A programmed with `0xABC` (2748), internal 2.5 V reference.
> Expected: $(2748 / 4096) \times 2.5\ \text{V} \approx 1.676\ \text{V}$
> Measured: **1.686 V**, noise **5.3 mV pk-pk**. ✓

### Analog limits to keep in mind
Even if the SPI bus is perfect, the DAC output has physical limits:

| Limit | AD5628 spec | Effect |
|-------|------------|--------|
| Output settling time | ~2.5 µs typ, 7 µs worst | Minimum interval between updates for full accuracy |
| Slew rate | ~1.2 V/µs | Caps the maximum sine frequency before distortion |

Maximum distortion-free sine frequency: $f_{max} = \frac{SR}{2\pi \cdot V_{pk}}$

---

⬅️ [MAIN PAGE ](../README.md)| ⬅️ [VHDL Pitfalls & Tricks](../gu01_vhdl_tricks/README.md)
