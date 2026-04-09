# AD5628 Datasheet Notes

## Device Overview

| Parameter | Value |
|-----------|-------|
| Channels | 8 independent DAC outputs (CH_A … CH_H) |
| Resolution | 12-bit (4096 steps) |
| VDD range | 2.7 V – 5.5 V |
| Interface | SPI-compatible, up to 50 MHz SCLK |
| Internal reference | 2.5 V, 5 ppm/°C, enabled via software command |
| POR state | Selectable: zero-scale or midscale (hardware pin) |
| Package | TSSOP-16 |

---

## Serial Interface

Data is clocked into the 32-bit shift register on the **falling edge of SCLK** (SPI Mode 2: CPOL=1, CPHA=0). SYNC (CS_N) is active-low.

On the 32nd falling SCLK edge the last bit is clocked in and the programmed function executes immediately. SYNC can be kept low or brought high at that point, but it **must be high for at least 15 ns** before the next write sequence can begin.

---

## 32-bit Command Frame

```
 Bits [31:28]   [27:24]   [23:20]   [19:8]      [7:4]   [3:0]
 ─────────────────────────────────────────────────────────────────
   0000          CMD       ADDR      DATA[11:0]  0000    0000
   (padding)                                     (don't care)
```

### Command Table (CMD field, bits [27:24])

| CMD  | Hex | Operation |
|------|-----|-----------|
| 0000 | 0   | Write to Input Register n |
| 0001 | 1   | Update DAC Register n (from Input Register) |
| 0010 | 2   | Write to Input Register n, update all DACs (SW LDAC) |
| 0011 | 3   | **Write to and Update DAC Channel n** ← normal use |
| 0100 | 4   | Power Down / Power Up DAC |
| 0101 | 5   | Hardware LDAC Mask Register |
| 0110 | 6   | Software Reset (POR) |
| 0111 | 7   | Set up internal reference register |
| 1000 | 8   | Set up DCEN register (daisy-chain enable) |

> **Critical:** Use CMD=`0011` to write and immediately update in one frame. CMD=`0001` only updates from the input register — it does nothing on first use when the input register has never been written.

### Channel Address Table (ADDR field, bits [23:20])

| ADDR | Channel |
|------|---------|
| 0000 | CH_A |
| 0001 | CH_B |
| 0010 | CH_C |
| 0011 | CH_D |
| 0100 | CH_E |
| 0101 | CH_F |
| 0110 | CH_G |
| 0111 | CH_H |
| 1111 | All channels simultaneously |

---

## Startup Sequence

The internal 2.5 V reference is **off by default** at power-on. It must be enabled with a dedicated command before any DAC write will produce a correct voltage.

**Frame 1 — Enable internal reference:**
```
0x08000001 = 0000 | 1000 | 0000_0000_0000_0000_0000 | 0001
```
Data bit 0 = `1` → reference on. Data bit 0 = `0` → reference off.

**Frame 2+ — Write and update a channel:**
```
0x030ABC00 = 0000 | 0011 | 0000 | 1010_1011_1100 | 0000_0000
              pad    CMD   CH_A    0xABC             don't care
```

---

## Output Voltage Formula

$$V_{out} = \frac{D}{4096} \times V_{REF}$$

With the internal 2.5 V reference and code `0xABC` (= 2748 decimal):

$$V_{out} = \frac{2748}{4096} \times 2.5\ \text{V} \approx 1.676\ \text{V}$$

HW measurement: **1.686 V** (Δ ≈ 10 mV, within gain + offset error budget).

---

## Accuracy Specifications

### Variables

| Symbol | Meaning |
|--------|---------|
| $D$ | Digital input code (0 – 4095) |
| $V_{LSB}$ | Ideal step size = $V_{REF} / 4096$ |
| $V_{ideal}(D)$ | $D \times V_{LSB}$ |
| $V_{out}(D)$ | Actual measured output |

### INL — Integral Nonlinearity

$$INL = \max \left| \frac{V_{out}(D) - V_{ideal}(D)}{V_{LSB}} \right|$$

Maximum deviation from the ideal straight-line transfer function. Spec: **±1 LSB**.

### DNL — Differential Nonlinearity

$$DNL = \frac{[V_{out}(D) - V_{out}(D-1)] - V_{LSB}}{V_{LSB}}$$

Deviation of a single step from the ideal 1 LSB. Spec: **±0.25 LSB**. Because DNL > −1 always, the output is **guaranteed monotonic** — no backwards steps.

### Zero-Code Error

$$E_{zero} = V_{out}(0)$$

Residual output voltage when D = 0. Spec: **19 mV max**.

### Full-Scale Error

$$E_{FS} = V_{out}(4095) - V_{ideal}(4095)$$

Total deviation at maximum code. Usually expressed as % of full-scale range.

### Gain Error

Deviation in the slope of the actual transfer function versus ideal, after removing offset error. Gets worse at higher codes (unlike offset error which is constant across all codes).

---

## Internal Reference

| Parameter | Value |
|-----------|-------|
| Voltage | 2.5 V |
| Drift | 5 ppm/°C |
| Default state | Off (must be enabled via software) |

**Temperature drift in context:** At 5 ppm/°C and 2.5 V reference, a 10 °C rise causes a 125 µV drift. One LSB at 12-bit = 610 µV. The drift is **5× smaller than 1 LSB**, so temperature effects are negligible in normal use.

---

## Output Stage

| Parameter | Value |
|-----------|-------|
| Slew rate | 1.5 V/µs |
| Settling time (¼ to ¾ scale) | 7 µs |
| Output type | Rail-to-rail |

The rail-to-rail output stage can swing the full supply range (0 V to VDD) without dead zones near the rails.

**Maximum update rate:** 1 / 7 µs ≈ **143 kHz** for fully settled output. Sending commands faster than this will cause the output to lag behind.

---

## Critical SPI Timing Constraints

| Symbol | Parameter | Min |
|--------|-----------|-----|
| t4 | SYNC low to first SCLK falling edge | 13 ns |
| t8 | SYNC high time between frames | 15 ns |
| t12 | Last SCLK falling edge to LDAC rising | 15 ns |

**t4 trap:** After asserting CS_N low, the FPGA state machine must wait at least one clock cycle before toggling SCLK. Dropping CS_N and SCLK on the same cycle violates the 13 ns setup time.

**t8 trap:** After the 32nd bit, CS_N must stay high for ≥ 15 ns before the next frame. At 12 MHz (83 ns/cycle) one idle cycle is more than sufficient. Violating this prevents the DAC from latching the command.

**t12:** Only relevant if LDAC is controlled by the FPGA. Not applicable when LDAC is hard-wired low.