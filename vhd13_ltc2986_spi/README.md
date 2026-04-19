# LTC2986 PT1000 Temperature Controller (VHDL)

A two-layer VHDL design that reads a **PT1000 4-wire RTD** using the
**LTC2986/LTC2986-1** multi-sensor temperature IC over SPI.
No hardware reset pin or /INTERRUPT pin is used — the controller
polls the status register over SPI to detect conversion completion.

---

## Source Files

| File | Description |
|------|-------------|
| [src/ltc2986_spi.vhd](src/ltc2986_spi.vhd) | Low-level SPI master — Mode 0, variable-length transactions, CS setup/idle timing |
| [src/ltc2986_ctrl.vhd](src/ltc2986_ctrl.vhd) | High-level controller — initialization, convert, poll, read result, continuous loop |
| [src/tb_ltc2986_ctrl.vhd](src/tb_ltc2986_ctrl.vhd) | Testbench — LTC2986 slave model, two full measurement cycles, self-checking assertions |

---

## Hardware

### Wiring — PT1000 4-wire RTD with 1.5 kΩ sense resistor

```
LTC2986                         Sense Resistor (1.5 kΩ, 1%)
  CH1 ──────────────────────────┤ low side
  CH2 ──────────────────────────┤ high side ──── force current path ──► PT1000 ──► CH1
                                                                           │
LTC2986                                                                    │
  CH3 ──────────────────────────── RTD Kelvin sense (+)                   │
  CH4 ──────────────────────────── RTD Kelvin sense (−) ──────────────────┘
```

More precisely, the current loop and Kelvin connections are:

```
  LTC2986
  ┌─────────────────────────────────────┐
  │ CH1 (IOUT−) ◄──┐                   │         ┌─── CH3 (VSENSE+)
  │                 │                   │         │
  │                RSense              FPGA      RTD ← Pt1000 (1 kΩ at 0°C)
  │                1500 Ω              SPI        │
  │                 │                   │         │
  │ CH2 (IOUT+) ────┘                   │         └─── CH4 (VSENSE−)
  └─────────────────────────────────────┘
```

| LTC2986 pin | Connects to | Role |
|-------------|-------------|------|
| CH1 | Sense resistor terminal 1 | Force current return |
| CH2 | Sense resistor terminal 2 | Force current source + RSense reference |
| CH3 | RTD Kelvin terminal + | Voltage sense (positive) |
| CH4 | RTD Kelvin terminal − | Voltage sense (negative) |
| SDI | FPGA MOSI | SPI data in |
| SDO | FPGA MISO | SPI data out |
| SCK | FPGA SCLK | SPI clock (max 2 MHz) |
| CS  | FPGA CS_n  | Chip select, active low |
| VCC | 3.3 V or 5 V | Supply (2.85 V–5.25 V range) |
| GND | GND | Common ground |

> **Note:** The LTC2986 reset pin and /INTERRUPT pin are left unconnected
> (or tied to VCC). The controller uses a 200 ms startup wait then polls
> the status register over SPI instead of using the interrupt.

---

## Module Overview

### Layer 1 — `ltc2986_spi` (low-level SPI master)

Handles raw byte-level transfers to/from any LTC2986 register.
Every transaction has a fixed 3-byte header followed by 1–4 data bytes:

```
Write:  CS↓  [0x02][addr_hi][addr_lo][byte0 … byteN−1]  CS↑
Read:   CS↓  [0x03][addr_hi][addr_lo]  ← N bytes in →   CS↑
```

**SPI mode:** Mode 0 (CPOL=0, CPHA=0) — SCK idles low, MOSI shifts on
falling edge, MISO sampled on rising edge, MSB first.

**Data word convention — left-justified in the 32-bit port:**

| Field | Meaning |
|-------|---------|
| `wr_data[31:24]` | First byte transmitted (MSB of payload) |
| `wr_data[23:16]` | Second byte |
| `wr_data[15:8]`  | Third byte |
| `wr_data[7:0]`   | Fourth byte |
| `rd_data[31:24]` | First byte received from device |
| `rd_data[23:0]`  | Remaining received bytes |

#### Generics

| Generic | Default | Description |
|---------|---------|-------------|
| `CLK_FREQ` | 100 000 000 | System clock frequency (Hz) |
| `SCLK_FREQ` | 2 000 000 | SCK frequency — must be ≤ 2 MHz for LTC2986 |
| `CS_SETUP_TICKS` | 11 | Sys-clk cycles CS_n held low before first SCK edge (≥ 100 ns t_CSS) |
| `CS_IDLE_TICKS` | 11 | Sys-clk cycles CS_n held high between frames |

#### Ports

| Port | Dir | Description |
|------|-----|-------------|
| `clk` | in | System clock |
| `start` | in | 1-cycle pulse: begin transaction |
| `rd_wr_n` | in | `'1'` = read (0x03), `'0'` = write (0x02) |
| `addr` | in | 16-bit LTC2986 register address |
| `n_bytes` | in | Number of data bytes (1–4) |
| `wr_data` | in | TX payload, left-justified 32-bit |
| `rd_data` | out | RX payload, left-justified 32-bit (valid when `done='1'`) |
| `busy` | out | High while transaction is in progress |
| `done` | out | 1-cycle pulse when transaction completes |
| `sclk/mosi/miso/cs_n` | — | SPI bus |

#### State Machine

```
IDLE ──(start)──► CS_SETUP ──(CS_SETUP_TICKS)──► SEND_BYTE ──(all bytes done)──► DONE_ST
                                                                                      │
IDLE ◄──(CS_IDLE_TICKS)── CS_IDLE ◄──────────────────────────────────────────────────┘
```

---

### Layer 2 — `ltc2986_ctrl` (measurement controller)

Wraps `ltc2986_spi` and runs the full measurement cycle autonomously.
Instantiate this in your top level — it needs only a clock and the 4-wire SPI bus.

#### Operation sequence

```
Power-on
   │
   ▼
STARTUP (STARTUP_TICKS cycles — default 200 ms)
   │
   ▼
INIT_GLOBAL ─── write 0x40 to 0x00F0  (50 Hz noise rejection)
   │
   ▼
INIT_RSENSE ─── write RSense config to CH2 address (0x0204)
   │
   ▼
INIT_RTD ──────  write RTD config to CH4 address (0x020C)
   │
   ┌──────────────────────────────────────────────────────┐
   ▼                                                      │
SEND_CONV ────── write 0x84 to 0x0000  (convert CH4)     │
   │                                                      │
   ▼                                                      │
CONV_WAIT ────── wait CONV_WAIT_TICKS (~100 ms)           │
   │                                                      │
   ▼                                                      │
POLL ───────────  read 1 byte from 0x0000                 │
   │                                                      │
   ▼                                                      │
CHECK_STATUS ──  bit 6 = '0'? ──────────────────► POLL   │
   │ bit 6 = '1' (done)                                   │
   ▼                                                      │
READ_RESULT ────  read 4 bytes from 0x001C (CH4 result)   │
   │                                                      │
   ▼                                                      │
temp_valid pulse, fault_code and temp_raw updated ────────┘
```

#### Generics

| Generic | Default | Description |
|---------|---------|-------------|
| `CLK_FREQ` | 100 000 000 | System clock (Hz) |
| `SCLK_FREQ` | 2 000 000 | SPI SCK (≤ 2 MHz) |
| `CH_RSENSE` | 2 | LTC2986 channel for the sense resistor (between CH1–CH2) |
| `CH_RTD` | 4 | LTC2986 channel for the RTD (Kelvin sense on CH3–CH4) |
| `STARTUP_TICKS` | 20 000 000 | Sys-clk cycles before first SPI access (~200 ms at 100 MHz) |
| `CONV_WAIT_TICKS` | 10 000 000 | Sys-clk cycles to wait after convert command (~100 ms at 100 MHz) |

#### Ports

| Port | Dir | Description |
|------|-----|-------------|
| `clk` | in | System clock |
| `temp_valid` | out | 1-cycle pulse each time a new reading is ready |
| `fault_code` | out | LTC2986 fault byte — `0x00` means no fault |
| `temp_raw` | out | 24-bit signed temperature, 1/1024 °C per LSB |
| `sclk/mosi/miso/cs_n` | — | SPI bus to LTC2986 |

---

## LTC2986 Register Configuration

### Global Configuration — `0x40` written to address `0x00F0`

Must be written once after power-on, before any channel config.
Bit 6 = `1` enables 50/60 Hz simultaneous rejection mode.
With 50 Hz rejection, a single-channel conversion takes approximately **170 ms**.

### Sense Resistor — `RSENSE_CFG = 0xE8177000`

Written to address **0x0204** (channel 2 assignment register).

| Bits | Value | Meaning |
|------|-------|---------|
| [31:27] | `11101` = 29 | Sensor type = Sense Resistor (type 29) |
| [26:0] | `0x177000` | Resistance = 1500 × 1024 = 1 536 000 (Q17.10, 1/1024 Ω LSB) |

Derivation: `1500 × 2^10 = 1 536 000 = 0x177000`, `29 << 27 = 0xE8000000`,
packed → `0xE8177000`.

### PT1000 RTD — `RTD_CFG` (computed from generics)

Written to address **0x020C** (channel 4 assignment register).

| Bits | Value | Meaning |
|------|-------|---------|
| [31:27] | `01111` = 15 | Sensor type = PT1000 4-wire RTD (type 15) |
| [26:22] | `00010` = CH2 | RSense on channel 2 |
| [21:20] | `10` | Excitation mode = 4-wire Kelvin sense |
| [19:16] | `0110` = 6 | Excitation current = 250 µA |
| [15:0] | `0` | — |

With `CH_RSENSE=2` this evaluates to **`0x78A60000`**.

VHDL formula:

```vhdl
constant RTD_CFG : std_logic_vector(31 downto 0) :=
  std_logic_vector(to_unsigned(
    15 * 16#8000000# +           -- type 15 → [31:27]=01111
    CH_RSENSE * 16#400000# +     -- RSense channel → [26:22]
    2 * 16#100000# +             -- 4-wire Kelvin mode → [21:20]=10
    6 * 16#10000#,               -- 250 µA excitation → [19:16]=0110
  32));
```

### Key Register Addresses (with default generics CH_RSENSE=2, CH_RTD=4)

| Address | Description |
|---------|-------------|
| `0x0000` | Command / Status register |
| `0x00F0` | Global configuration register |
| `0x0204` | Channel 2 assignment (RSense config) |
| `0x020C` | Channel 4 assignment (RTD config) |
| `0x001C` | Channel 4 temperature result (4 bytes) |

---

## Temperature Output Format

`temp_raw` is a **24-bit signed value** (two's complement).
The LSB represents **1/1024 °C**.

```
Temperature (°C) = to_integer(signed(temp_raw)) / 1024
```

Examples:

| `temp_raw` (hex) | Decimal | Temperature |
|------------------|---------|-------------|
| `0x006400` | +25 600 | +25.000 °C |
| `0x000400` | +1 024 | +1.000 °C |
| `0x000001` | +1 | +0.000977 °C |
| `0x000000` | 0 | 0.000 °C |
| `0xFFFC00` | −1 024 | −1.000 °C |

`fault_code` (upper 8 bits of the raw 32-bit result):

| Bit | Meaning |
|-----|---------|
| 7 | Valid (should be `1` for a good reading) |
| 6 | ADC out of range |
| 5 | Sensor open circuit |
| 4 | Sensor short to VCC |
| 3 | Sensor short to GND |
| 2–0 | Reserved |

`0x00` means all fault bits clear. Check the LTC2986 datasheet
Table 13 for the full fault byte definition.

---

## Testbench — `tb_ltc2986_ctrl`

### Parameters

| Parameter | Value | Note |
|-----------|-------|------|
| `CLK_FREQ` | 10 MHz | Fast simulation clock |
| `SCLK_FREQ` | 1 MHz | SCK → HALF_PER = 5 cycles |
| `STARTUP_TICKS` | 10 | 1 µs startup delay (instead of 200 ms) |
| `CONV_WAIT_TICKS` | 10 | 1 µs conversion wait (instead of 100 ms) |
| `CH_RSENSE` | 2 | Matches hardware |
| `CH_RTD` | 4 | Matches hardware |

One byte transfer = 80 ns. Full 7-byte transaction ≈ 560 ns.
Total simulation time for two complete cycles ≈ 15 µs.

### Simulated slave responses

| Transaction | Type | MISO data (data bytes only) |
|-------------|------|-----------------------------|
| 1 | Global config write | — (don't care) |
| 2 | RSense write | — (don't care) |
| 3 | RTD write | — (don't care) |
| 4 | Convert write | — (don't care) |
| 5 | Status read | `0x00` (conversion busy) |
| 6 | Status read | `0x40` (bit 6 = done) |
| 7 | Result read | `0x00 0x00 0x64 0x00` (25.000 °C) |
| 8 | Convert write | — (second cycle) |
| 9 | Status read | `0x40` (done immediately) |
| 10 | Result read | `0x00 0x00 0x64 0x00` (25.000 °C) |

### Expected output after each result read

```
fault_code = 0x00
temp_raw   = 0x006400   →   25.000 °C
temp_valid = '1'  (for one clock cycle)
```

Self-checking `assert` statements verify both readings.
Simulation ends with `severity failure` after the second result
(standard clean-stop idiom for Vivado/GHDL).

### Adding to Vivado simulation

1. Add all three source files to the project:
   - `src/ltc2986_spi.vhd`
   - `src/ltc2986_ctrl.vhd`
   - `src/tb_ltc2986_ctrl.vhd`
2. Set `tb_ltc2986_ctrl` as the simulation top.
3. Run behavioural simulation — check TCL console for PASS/FAIL messages.

---

## Adding to a Vivado Synthesis Project

Instantiate `ltc2986_ctrl` in your top-level design:

```vhdl
U_LTC : entity work.ltc2986_ctrl
  generic map (
    CLK_FREQ        => 100_000_000,  -- match your system clock
    SCLK_FREQ       => 2_000_000,
    CH_RSENSE       => 2,
    CH_RTD          => 4,
    STARTUP_TICKS   => 20_000_000,   -- 200 ms at 100 MHz
    CONV_WAIT_TICKS => 10_000_000    -- 100 ms at 100 MHz (conversion ~170 ms)
  )
  port map (
    clk        => sys_clk,
    temp_valid => temp_valid,
    fault_code => fault_code,
    temp_raw   => temp_raw,
    sclk       => ltc_sclk,
    mosi       => ltc_mosi,
    miso       => ltc_miso,
    cs_n       => ltc_cs_n
  );
```

Add the four SPI signals (`ltc_sclk`, `ltc_mosi`, `ltc_miso`, `ltc_cs_n`)
to your XDC constraints file with the correct FPGA pin numbers and an
`IOSTANDARD` matching the LTC2986 supply voltage (typically `LVCMOS33`).

Example XDC snippet:

```tcl
set_property PACKAGE_PIN  <PIN>  [get_ports ltc_sclk]
set_property IOSTANDARD   LVCMOS33 [get_ports ltc_sclk]
set_property PACKAGE_PIN  <PIN>  [get_ports ltc_mosi]
set_property IOSTANDARD   LVCMOS33 [get_ports ltc_mosi]
set_property PACKAGE_PIN  <PIN>  [get_ports ltc_miso]
set_property IOSTANDARD   LVCMOS33 [get_ports ltc_miso]
set_property PACKAGE_PIN  <PIN>  [get_ports ltc_cs_n]
set_property IOSTANDARD   LVCMOS33 [get_ports ltc_cs_n]
```

---

## Timing Summary (100 MHz system clock, 2 MHz SCK)

| Parameter | Value | LTC2986 Spec |
|-----------|-------|--------------|
| SCK period | 500 ns | ≥ 500 ns (2 MHz max) ✓ |
| SCK high/low time | 250 ns | ≥ 250 ns ✓ |
| CS_n setup (t_CSS) | 110 ns | ≥ 100 ns ✓ |
| CS_n idle | 110 ns | no hard spec |
| Startup wait | 200 ms | LTC2986 POR settle |
| Conversion wait (before poll) | 100 ms | Conversion ~170 ms with 50 Hz filter |
| Conversion time (PT1000, 50 Hz) | ~170 ms | single channel, 50 Hz rejection |

---

## Known Limitations

| Limitation | Impact |
|------------|--------|
| No reset port | Relies on power-on reset; STARTUP_TICKS must cover LTC2986 POR time |
| Continuous conversion only | Controller loops forever; there is no external trigger for one-shot operation |
| Single channel only | Measures CH_RTD only; extend SEND_CONV and READ_RESULT states for multi-channel |
| No MISO synchroniser | Add a 2-FF synchroniser on `miso` if it comes from a noisy or long PCB trace |

---

## References

1. LTC2986/LTC2986-1 Datasheet — Analog Devices
2. [vhd12 — SPI Master with CS Timing](../vhd12_cs_timing/README.md) (parent SPI module)

---

⬅️ [MAIN PAGE](../README.md) | ⬅️ [SPI CS Timing](../vhd12_cs_timing/README.md)
