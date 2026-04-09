# SPI Master with CS Setup/Idle Timing (VHDL)

A synthesizable, full-duplex **SPI Master** extending [vhd11](../vhd11_spi_all_modes/README.md) (all 4 modes)
with two additional timing generics: **`CS_SETUP_TICKS`** (CS assert → first SCK edge) and
**`CS_IDLE_TICKS`** (CS deassert hold time between frames).
Required by many devices — for example the AD5628 DAC specifies t_CSS and t8 minimums.

---

## Source Files

| File | Description |
|------|-------------|
| `src/spi_cs_timing.vhd`    | SPI master RTL — 5-state FSM, all 4 modes, configurable CS timing |
| `src/tb_spi_cs_timing.vhd` | Testbench — Mode 2 (CPOL=1, CPHA=0), single transaction, waveform inspection |

---

## SPI Mode Summary

| Mode | CPOL | CPHA | SCK idle | Sample edge | Shift edge |
|------|------|------|----------|-------------|------------|
| 0    | 0    | 0    | LOW      | Rising      | Falling    |
| 1    | 0    | 1    | LOW      | Falling     | Rising     |
| 2    | 1    | 0    | HIGH     | Falling     | Rising     |
| 3    | 1    | 1    | HIGH     | Rising      | Falling    |

---

## Features

* **All 4 SPI modes** — single RTL source, mode selected by `CPOL`/`CPHA` generics
* **CS_SETUP_TICKS** — guaranteed setup time from CS_n assert to first SCK edge (t_CSS)
* **CS_IDLE_TICKS** — guaranteed CS_n high time between consecutive frames (t8)
* Both timing generics accept `0` to bypass their states and go straight to TRANSFER/IDLE
* **Timer-based edge detection** — SCK edges inferred from half-period timer, zero extra latency
* **Deterministic SCK phase** — timer resets on every transaction start
* **CPHA=0:** MSB pre-loaded onto MOSI before CS_n asserts
* **CPHA=1:** full TX word loaded at start; first bit driven on first SCK edge
* **Full-duplex** — TX and RX shift registers operate simultaneously
* One-cycle `done` pulse; `busy` held high for full transaction duration

---

## State Machine

```
IDLE ──(start)──► CS_SETUP ──(CS_SETUP_TICKS)──► TRANSFER ──(all bits done)──► DONE_ST
                                                                                    │
IDLE ◄──(CS_IDLE_TICKS)── CS_IDLE ◄────────────────────────────────────────────────┘
```

| State      | Action |
|------------|--------|
| `IDLE`     | `busy='0'`, `cs_n='1'`. On `start`: asserts `cs_n`, loads TX data, resets timer |
| `CS_SETUP` | Holds CS_n low for `CS_SETUP_TICKS` cycles before first SCK edge |
| `TRANSFER` | Toggles SCK every `HALF_PER` cycles; shifts TX/RX data |
| `DONE_ST`  | Single cycle: deasserts `cs_n`, latches received data, pulses `done` |
| `CS_IDLE`  | Holds CS_n high for `CS_IDLE_TICKS` cycles before returning to IDLE |

---

## Generics

| Generic          | Default         | Description |
|------------------|-----------------|-------------|
| `CLK_FREQ`       | `100_000_000`   | System clock frequency (Hz) |
| `SCLK_FREQ`      | `50_000_000`    | Desired SCK frequency (Hz) |
| `DATA_W`         | `32`            | Transaction width (bits) |
| `CPOL`           | `'1'`           | Clock polarity: `'0'` = idle low, `'1'` = idle high |
| `CPHA`           | `'0'`           | Clock phase: `'0'` = sample-first, `'1'` = shift-first |
| `CS_SETUP_TICKS` | `1`             | Sys-clk cycles from CS assert to first SCK edge (t_CSS). `0` = skip CS_SETUP state |
| `CS_IDLE_TICKS`  | `1`             | Sys-clk cycles CS_n must stay high between frames (t8). `0` = skip CS_IDLE state |

---

## Ports

| Port                   | Direction | Description |
|------------------------|-----------|-------------|
| `clk`                  | in  | System clock |
| `start`                | in  | One-cycle pulse to begin a transaction |
| `busy`                 | out | High while a transaction is in progress |
| `done`                 | out | One-cycle pulse when transaction completes |
| `mosi_dat[DATA_W-1:0]` | in  | Data to transmit (MSB first) |
| `miso_dat[DATA_W-1:0]` | out | Received data, valid on `done` |
| `sclk`                 | out | SPI clock — active only during TRANSFER |
| `mosi`                 | out | Master Out Slave In |
| `miso`                 | in  | Master In Slave Out |
| `cs_n`                 | out | Chip select, active low |

---

## Testbench (`tb_spi_cs_timing.vhd`)

Single DUT in **Mode 2** (CPOL=1, CPHA=0) with `CS_SETUP_TICKS=3`, `CS_IDLE_TICKS=3`.

| Parameter    | Value |
|--------------|-------|
| CLK_FREQ     | 100 MHz |
| SCLK_FREQ    | 50 MHz |
| DATA_W       | 8 bits |
| CS_SETUP     | 3 cycles |
| CS_IDLE      | 3 cycles |
| Master sends | `0xA5` |
| Slave sends  | `0x3C` |

The behavioral slave loads on CS_n falling edge and shifts MISO out on SCK rising edge.
`miso_dat` captures `0x3C` on `done`. Inspect `cs_n`, `sclk`, `mosi`, `miso`, `miso_dat`,
and the slave `shreg` shift register in the waveform viewer.

![Testbench waveform — CS Setup/Idle timing](docs/tb_cs_timing.png)

---

## Known Limitations

| Limitation | Impact |
|------------|--------|
| No reset port | Relies on signal initializers for power-on state (fine for Xilinx GSR) |
| `HALF_PER` must be ≥ 1 | `SCLK_FREQ` must not exceed `CLK_FREQ / 2` |
| No MISO synchronizer | Metastability risk on MISO in noisy environments |
| MSB-first only | LSB-first devices require external bit reversal |
| Single CS_n | Multi-slave designs need external chip-select decoding |

---

## References

1. [Understanding SPI](https://www.youtube.com/watch?v=0nVNwozXsIc)
2. [Serial Peripheral Interface — Wikipedia](https://en.wikipedia.org/wiki/Serial_Peripheral_Interface)
3. AD5628 Datasheet — t_CSS (CS setup) and t8 (CS idle) timing specifications

---

<= [MAIN PAGE](../README.md)
