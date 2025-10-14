# UART Receiver (VHDL)

A compact, synthesizable **UART RX** for FPGA boards (verified with **CMOD A7** loopback and a self-checking testbench). The receiver targets the classic **8-N-1/2** framing (8 data bits, no parity, 1 or 2 stop bits transmitted by the peer). Line idles high; data is LSB-first.

---

## Features

* **Parametric** clock and baud via generics
  `CLK_FREQ`, `BAUD_RATE`
* **Single-sample, mid-bit timing** (no oversampling) with clean start-bit qualification
* One-byte output with a **read strobe** `read_done` asserted for one bit period after a valid frame
* Straightforward 4-state FSM

---

## UART Frame (what the RX expects)

Idle `1` → **Start** `0` → **D0..D7** (LSB first) → **Stop** `1` (at least one)

![timing](../p11_uart_rx/docs/uart_timing.png)

---

## Architecture

### Parameters

Bit timing derived from the system clock:

$$
BAUD\_TICKS=\frac{CLK\_FREQ}{BAUD\_RATE}
$$

Internal counters:

* `timer` — counts `0 .. BAUD_TICKS−1`
* `bit_cnt` — counts received data bits `0 .. 7`

### State machine

![fsm](docs/fsm_rx.png)

`IDLE → START → DATA → STOP → IDLE`

* **IDLE**
  Wait for falling edge (`rx_in='0'`).

* **START**
  Wait **half a bit** (mid-start) and re-sample.
  If still `0`, the start is valid → load `DATA`; otherwise return to `IDLE`.

* **DATA**
  Every `BAUD_TICKS`, sample `rx_in` and shift into a byte (LSB first).
  After 8 bits, proceed to `STOP`.

* **STOP**
  After one full bit time at logic `1`, present the byte on `data_out` and assert `read_done='1'` for one bit interval, then return to `IDLE`.

> Notes
> • The RX tolerates **1 or more** stop bits on the line (peer-selectable).
> • No parity is checked. Extend by inserting a PARITY state if needed.

---

## I/O

* `rx_in` — asynchronous serial input (idle high)
* `data_out[7:0]` — captured byte, valid when `read_done='1'`
* `read_done` — one-shot pulse after a valid frame

---

## Top-level example (CMOD A7)

In the top module assigned the last two bits of the received data to the LEDs since CMOD A7 only have 2 LEDs.

---

## Testbench

`tb_uart_rx.vhd` drives a synthesized UART waveform into `rx_in`:

* 100 MHz clock
* Baud = 115 200
* Sends a few bytes with proper start/stop timing
* Checks `read_done` and captures `data_out`

Waveforms shows mid-bit sampling at the centers of each data bit and a clean `read_done` pulse after the stop bit.

![tb](docs/tb.png)
---

## Files

* `uart_rx.vhd` — receiver RTL
* `top.vhd` — CMOD A7 demo wrapper
* `tb_uart_rx.vhd` — simulation testbench


## References

1. [Mehmet Burak Aykenar – GitHub](https://github.com/mbaykenar/apis_anatolia)

---

⬅️  [MAIN PAGE](../README.md)
