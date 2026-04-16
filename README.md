# LOGIC PLAYGROUND

A structured personal reference for FPGA development — covering RTL fundamentals, toolflow, and IP integration, built on Xilinx/Vivado with VHDL.

---

## Guides & References

| # | Guide | Topic |
|---|-------|-------|
| 0 | [VHDL Template & Syntax Notes](vhd00_vhdl_template/README.md) | Entity/architecture structure, coding conventions |
| 1 | [VHDL Notes: Behaviors, Pitfalls, and Useful Tricks](vhd01_vhdl_tricks/README.md) | Signal vs variable timing, latch prevention, CDC |
| 2 | [Peripheral Driver Development Guide](g00_peripheral_guide/README.md) | Datasheet → architecture → VHDL → simulation → hardware |

---

## VHDL / RTL Design

| # | Project | Key Concept |
|---|---------|-------------|
| 0 | [N-Bit Adder with VIO (Cmod A7)](vhd02_adder_vio/README.md) | `generate` loops for parametric design, VIO debugging |
| 1 | [Debouncer (FSM)](vhd03_debouncer/README.md) | FSM + timer integration, metastability from external inputs |
| 2 | [Button-Selectable Timer & LED Counter](vhd04_tim_cnt/README.md) | Module cascading, edge detection, clock-derived timing |
| 3 | [Tick-Based PWM Output Module](vhd05_pwm_tick_out/README.md) | Double-buffered duty cycle for glitch-free updates |
| 4 | [Percentage-based PWM Output](vhd06_pwm_percent/README.md) | Integer rounding (add-50/divide-100), period-boundary latching |
| 5 | [UART Transmitter](vhd07_uart_tx/README.md) | Bit-timing via counter FSM, shift register TX |
| 6 | [UART Receiver](vhd08_uart_rx/README.md) | Mid-bit sampling (T/2 start, then every T), frame validation |
| 7 | [BRAM Usage — Single-Port Block RAM](vhd09_block_ram/README.md) | BRAM inference, READ/WRITE_FIRST modes, pipeline latency |
| 8 | [SPI Master — Mode 0](vhd10_spi_mode0/README.md) | Timer-based edge detection, deterministic SCK phase |
| 9 | [SPI Master — All Modes](vhd11_spi_all_modes/README.md) | CPOL/CPHA generics, all 4 SPI modes from one RTL source |
| 10 | [SPI Master — With CS/Idle Timing](vhd12_cs_timing/README.md) | Parameterized CS and IDLE delay times, dead-time enforcement between frames |

---

## Mini Projects

| # | Project | Key Concept |
|---|---------|-------------|
| 0 | [Sawtooth Wave Generator via PmodDA4](p00_sawtooth_dac/README.md) | Clock Wizard IP (12→100 MHz), 50 MHz SPI, pipelined waveform generation |

---

## IP Cores

| # | Project | Key Concept |
|---|---------|-------------|
| 0 | [Sine Wave Generation using Xilinx DDS Compiler](ip00_sine_dds_block/README.md) | Phase accumulator, Frequency Tuning Word calculation |

---

## Drivers

| # | Project | Key Concept |
|---|---------|-------------|
| 0 | [PmodDA4 Driver — Digilent reference adaptation](d00_pmodda4_driver/README.md) | SPI frame construction, analog slew rate constraints |
| 1 | [PmodDA4 Driver — AD5628 with Universal SPI Master](d01_pmodda4/README.md) | From-scratch FSM over generic SPI IP, INIT_REF sequencing, CS/idle timing constraints |

---

## MicroBlaze (Soft Processor)

| # | Project | Key Concept |
|---|---------|-------------|
| 0 | [MicroBlaze General Notes](uB00_uBlaze_notes/README.md) | Core presets, max frequencies, multi-core TMR pattern |
| 1 | [MicroBlaze GPIO](uB01_uBlaze_gpio/README.md) | Vivado block design flow, XSA export, Vitis platform + app project setup |

---

## Vivado Toolflow

| # | Topic | Key Concept |
|---|-------|-------------|
| 0 | [Vivado Troubleshooting Log](viv00_troubleshoots/README.md) | Running log of Vivado issues and fixes |
| 1 | [Programming FPGA with Quad SPI Flash](viv01_programming_fpga/README.md) | Bitstream compression, QSPI flash programming workflow |


---

## DSP

| # | Project | Key Concept |
|---|---------|-------------|
| 0 | `dsp00_dds_from_scratch` — *coming soon* | Phase accumulator, ROM LUT, frequency resolution |

---

## References & Acknowledgements

This repository draws on Xilinx/AMD documentation, HDL textbooks, YouTube tutorials, and community resources. Original sources are cited within each subproject's README.
