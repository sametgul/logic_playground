# LOGIC PLAYGROUND

A structured personal reference for FPGA development — covering RTL fundamentals, toolflow, and IP integration, built on Xilinx/Vivado with VHDL.

**Board:** Digilent Cmod A7 (Artix-7, 12 MHz oscillator)

---

## VHDL / RTL Design

| # | Project | Key Concept |
|---|---------|-------------|
| 0 | [VHDL Template & Syntax Notes](vhd00_vhdl_template/README.md) | Entity/architecture structure, coding conventions |
| 1 | [VHDL Notes: Behaviors, Pitfalls, and Useful Tricks](vhd01_vhdl_tricks/README.md) | Signal vs variable timing, latch prevention, CDC |
| 2 | [N-Bit Adder with VIO (Cmod A7)](vhd02_adder_vio/README.md) | `generate` loops for parametric design, VIO debugging |
| 3 | [Debouncer (FSM)](vhd03_debouncer/README.md) | FSM + timer integration, metastability from external inputs |
| 4 | [Button-Selectable Timer & LED Counter](vhd04_tim_cnt/README.md) | Module cascading, edge detection, clock-derived timing |
| 5 | [Tick-Based PWM Output Module](vhd05_pwm_tick_out/README.md) | Double-buffered duty cycle for glitch-free updates |
| 6 | [Percentage-based PWM Output](vhd06_pwm_percent/README.md) | Integer rounding (add-50/divide-100), period-boundary latching |
| 7 | [UART Transmitter](vhd07_uart_tx/README.md) | Bit-timing via counter FSM, shift register TX |
| 8 | [UART Receiver](vhd08_uart_rx/README.md) | Mid-bit sampling (T/2 start, then every T), frame validation |
| 9 | [BRAM Usage — Single-Port Block RAM](vhd09_block_ram/README.md) | BRAM inference, READ/WRITE_FIRST modes, pipeline latency |
| 10 | [SPI Master — Mode 0](vhd10_spi_master/README.md) | Timer-based edge detection, deterministic SCK phase |

---

## IP Cores

| # | Project | Key Concept |
|---|---------|-------------|
| 0 | [Sine Wave Generation using Xilinx DDS Compiler](ip00_sine_dds_block/README.md) | Phase accumulator, Frequency Tuning Word calculation |

---

## Drivers

| # | Project | Key Concept |
|---|---------|-------------|
| 0 | [PMODDA4 Driver — DAC AD5628](d01_pmodda4_driver/README.md) | SPI frame construction, analog slew rate constraints |

---

## Vivado Toolflow

| # | Topic | Key Concept |
|---|-------|-------------|
| 0 | [Programming FPGA with Quad SPI Flash](v00_programming_fpga/README.md) | Bitstream compression, QSPI flash programming workflow |

---

## References & Acknowledgements

This repository draws on Xilinx/AMD documentation, HDL textbooks, YouTube tutorials, and community resources. Original sources are cited within each subproject's README.
