# UART Transmitter (VHDL)

A minimal, synthesizable UART **TX** for FPGA boards (tested on **CMOD A7**) and a clean testbench. The design is **8-N-1 or 8-N-2** selectable via generic (8 data bits, no parity, 1 or 2 stop bits), LSB-first, idle level high.

---

## Features

* **Parametric** clock, baud rate, and stop bit count via `CLK_FREQ`, `BAUD_RATE`, `STOP_BITS` generics
* **One-byte shifter** (no FIFO) — `start_tx` is sampled only in `IDLE`, pulses during busy states are ignored
* **Status output** `tx_done` asserted at the entry of the `END` state, held high for the stop bit period(s)
* Compact 4-state FSM: `IDLE → START → DATA → END → IDLE`

---

## UART Frame

Idle line is `'1'`. A frame is:

* **Start bit**: `'0'` for one bit period
* **8 data bits**: LSB first
* **STOP_BITS** stop bits: `'1'`

![timing](docs/uart_timing.png)

---

## Architecture

### State Machine

![fsm](docs/fsm.png)

* `IDLE`: line high, waits for `start_tx = '1'`
* `START`: drives `'0'` for one bit period, loads shift register
* `DATA`: outputs 8 bits LSB-first, shifts right each bit period, `bit_cnt` tracks position
* `END`: outputs `'1'` for `STOP_BITS` bit periods, asserts `tx_done`

### Bit Timing

A simple integer timer generates bit periods:

$$
TIMER\_LIM=\frac{CLK\_FREQ}{BAUD\_RATE},\qquad
STOP\_LIM= TIMER\_LIM \times STOP\_BITS
$$

No oversampling — the TX side only needs period accuracy.

Key internal signals:

| Signal       | Description                          |
|--------------|--------------------------------------|
| `timer`      | counts `0 .. TIMER_LIM-1`            |
| `stop_timer` | counts stop-bit clocks               |
| `shreg`      | 8-bit shift register (data)          |
| `bit_cnt`    | bit position counter, `0 .. 7`       |

---

## Top-level Example (CMOD A7)

`top.vhd` sends an incrementing byte once per second (`CLK_FREQ = 12 MHz`), toggling the onboard LED via `tx_done`. Connect `uart_rxd_out` to your USB-UART RXD pin.

Generics used:

* `CLK_FREQ  => 12_000_000`
* `BAUD_RATE => 115_200`
* `STOP_BITS => 1`

Pinout (adapt to your XDC):

* `sysclk` → 12 MHz onboard clock
* `uart_rxd_out` → FTDI RX pin
* `led` → user LED

---

## Testbench

Self-contained testbench (`tb_uart_tx.vhd`) with a 100 MHz clock:

* Sends `0xAB`, waits for the full stop period, then sends `0xCD`
* Uses `STOP_BITS = 2` to make the stop interval clearly visible in waveforms
* Ends with `assert false report "SIM DONE" severity failure`

Expected waveform:

![testbench](docs/testbench.png)

---

## Integration Tips

* **Back-to-back bytes**: pulse `start_tx` again any time after `tx_done` goes low (i.e. after `END → IDLE` transition)
* **Throughput**: with `STOP_BITS = 1`, the line is ready for the next start bit immediately after the stop bit
* **Glitch-free start**: `start_tx` is only sampled in `IDLE` — pulses during busy states are safely ignored
* **Reset**: design relies on power-up defaults; add an explicit synchronous reset if your toolflow requires it
* **Parity**: not implemented — easiest extension is to insert a `PARITY` state between `DATA` and `END`

## References

1. [Mehmet Burak Aykenar - Github](https://github.com/mbaykenar/apis_anatolia)

---
⬅️  [MAIN PAGE](../README.md)