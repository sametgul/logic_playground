# Peripheral Driver Development Guide

A step-by-step methodology for writing FPGA peripheral drivers in VHDL — from reading the datasheet to verifying the analog output on the bench. Every step is illustrated with the **AD5628 (PmodDA4)** DAC driver as a worked example.

---

## Step 1 — Datasheet

Before writing any VHDL, extract these four things from the datasheet:

### SPI Mode
Identify CPOL and CPHA from the timing diagram — do not rely on the mode number alone, different vendors label them differently. Check:
- What level does SCLK idle at? (`CPOL`)
- Is data sampled on the first or second edge? (`CPHA`)

> **AD5628 example:** SCLK idles HIGH, data clocked in on the **falling** edge → Mode 2 (CPOL=1, CPHA=0).

### Frame Format
Identify the bit width, field positions, and MSB/LSB order.

> **AD5628 example:** 32-bit frame, MSB first.
> ```
>  [31:28]  [27:24]  [23:20]  [19:8]      [7:0]
>  PAD(4)   CMD(4)   ADDR(4)  DATA(12)    PAD(8)
> ```

### Timing Constraints
Look for setup/hold times around CS and SCLK, minimum CS high time between frames, and maximum SCLK frequency.

> **AD5628 example:**
> | Constraint | Spec | Impact |
> |------------|------|--------|
> | t4 — CS↓ to first SCLK edge | ≥ 13 ns | `CS_SETUP_TICKS ≥ 1` at 100 MHz |
> | t8 — CS high between frames | ≥ 15 ns | `CS_IDLE_TICKS ≥ 2` at 100 MHz |
> | Max SCLK | 50 MHz | `HALF_PER ≥ 1` at 100 MHz system clock |

### Startup Sequence
Check whether the peripheral needs an initialisation command before normal operation.

> **AD5628 example:** Internal reference is disabled by default. Must send `0x08000001` (enable internal 2.5 V reference) before the first DAC write, otherwise output is 0 V regardless of what you write.

---

## Step 2 — Architecture

Sketch the module hierarchy **on paper before writing a line of VHDL**.

A peripheral driver typically has three layers:

```
waveform_gen / stimulus
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

Write the **innermost module first**, work outward. Each module must have a clean, tested port contract before the next layer is written.

**Order for a typical SPI peripheral:**
1. SPI core (`spi_cs_timing`) — timer, edge detect, shift register
2. Driver wrapper (`PmodDA4`) — frame assembly, init sequence FSM
3. Stimulus / waveform gen (`sawtooth_gen`) — generates the data stream
4. Top level (`top_sawtooth`) — wires everything, instantiates clock IP

**Key VHDL conventions** (see also [vhd00](../vhd00_vhdl_template/README.md)):
- One entity per file, filename matches entity name
- All registers on `rising_edge(clk)`, no asynchronous resets unless required
- Generics for anything that might change: `CLK_FREQ`, `SCLK_FREQ`, `DATA_W`, `CPOL`, `CPHA`
- Default pulse signals to `'0'` at the top of the clocked process; assert for exactly one cycle

---

## Step 4 — Unit Simulation

Write a **testbench per module** with self-checking assertions. Do not move to the next layer until this one passes.

**Testbench essentials:**
- A behavioral slave model (shift register clocked on the correct SPI edge)
- Assertions that check the exact bit pattern received, not just "something arrived"
- An `assert FALSE report "SIM DONE" severity failure` at the end to stop the simulator cleanly

**Slave model edge convention:**

| SPI Mode | Slave shifts MISO on | Master samples MISO on |
|----------|---------------------|------------------------|
| Mode 0 (CPOL=0, CPHA=0) | Falling SCK | Rising SCK |
| Mode 1 (CPOL=0, CPHA=1) | Rising SCK | Falling SCK |
| Mode 2 (CPOL=1, CPHA=0) | Rising SCK | Falling SCK |
| Mode 3 (CPOL=1, CPHA=1) | Falling SCK | Rising SCK |

> **AD5628 example (Mode 2):** slave captures MOSI on every **falling** SCLK edge.
> ```vhdl
> p_SLAVE : process (cs_n, sclk) begin
>   if    falling_edge(cs_n)  then shreg <= (others => '0');
>   elsif falling_edge(sclk)  then shreg <= shreg(30 downto 0) & mosi;
>   end if;
> end process;
> ```
> Assertion: `assert shreg = x"030ABC00"` after transaction completes.

**Common pitfall — CPHA=1 last-bit capture:** when `bit_cnt = DATA_W-1`, the final MISO bit shift into `rx_shreg` and the `miso_dat <= rx_shreg` assignment happen in the same clock cycle. Since both are registered, `miso_dat` captures the stale value (one bit short). Fix: use the expression directly — `miso_dat <= rx_shreg(DATA_W-2 downto 0) & miso` — on the last bit for CPHA=1.

---

## Step 5 — Integration Simulation

Simulate the **full chain**: stimulus → driver wrapper → SPI pins. Verify:

- The init sequence fires exactly once on the first `start` pulse
- Frame content is correct for multiple transactions
- `busy` / `done` handshaking works correctly across the module boundary
- CS timing constraints are met (count the clock cycles between CS↓ and first SCLK edge)

> **AD5628 example:** `tb_PmodDA4.vhd` drives two back-to-back DAC writes and asserts both 32-bit frames — the INIT_REF frame (`0x08000001`) followed by the data frame (`0x030ABC00`).

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
Capture the SPI bus and verify frame content matches simulation.

| Tool | What to check |
|------|--------------|
| Saleae / Analog Discovery | CS timing (t4, t8), frame bit pattern, SCLK frequency |
| Vivado ILA | Same, but triggered on internal signals |

Configure the decoder: CS active-low, correct CPOL/CPHA, 32-bit MSB-first.

> **AD5628 example:** WaveForms SPI decoder — `CS=DIO0 (Active Low)`, `CLK=DIO2 (Falling sample)`, `Data=DIO1`, 32-bit MSB hex.

### Oscilloscope second
Once frames are confirmed correct, verify the analog output.

- Check the DC level for a fixed code: $V_{out} = \frac{D}{4096} \times V_{ref}$
- For a waveform, check frequency, amplitude, and shape
- Check for glitches at code boundaries (large steps expose slew-rate limits)

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

## Worked Examples in this Repo

| Step | d00 (reference adapt) | d01 (from scratch) | p00 (sawtooth) |
|------|-----------------------|--------------------|----------------|
| Datasheet | AD5628 SPI mode, frame, t4/t8 | same | same |
| Architecture | Digilent FSM + SPI | custom SPI + wrapper | adds clock wizard + sawtooth gen |
| Bottom-up VHDL | adapted from Digilent | spi_all_modes → PmodDA4 | spi_cs_timing → PmodDA4 → sawtooth_gen |
| Unit sim | tb_pmodda4 | tb_PmodDA4, tb_spi_all_modes | tb_PmodDA4 |
| Integration sim | full chain | full chain | full chain |
| Synthesis | Cmod A7 | Cmod A7 | Cmod A7 |
| Hardware | ZYBO Z7 scope capture | Analog Discovery 3 | AD3 logic analyzer at 12.5 MHz (50 MHz too fast for AD3), scope 353.83 Hz |

---

⬅️ [MAIN PAGE](../README.md) | [VHDL Template](../vhd00_vhdl_template/README.md) | [VHDL Pitfalls & Tricks](../vhd01_vhdl_tricks/README.md) | [PmodDA4 Reference](../d00_pmodda4_driver/README.md) | [PmodDA4 From Scratch](../d01_pmodda4/README.md) | [Sawtooth DAC](../p00_sawtooth_dac/README.md)
