# UART Transmitter (VHDL)

A minimal, synthesizable UART **TX** for FPGA boards (tested on **CMOD A7**) and a clean testbench. The design is **8-N-1/2** style (8 data bits, no parity, 1 or 2 stop bits), LSB-first, idle level high.

---

## Features

* **Parametric** clock, baud, and stop bits
  `CLK_FREQ`, `BAUD_RATE`, `STOP_BIT` generics
* **One-byte shifter** (no FIFO) — new `start_tx` is sampled only in `IDLE`
* **Status output** `tx_done` goes high during the stop bit period(s)
* Compact 4-state FSM: `IDLE → START → DATA → END → IDLE`

---

## UART Frame

Idle line is `1`. A frame is:

* **Start** bit: `0`
* **8 data bits**: LSB first
* **STOP_BIT** stop bits: `1`

![timing](docs/uart_timing.png)

---

## Architecture

### State machine

![fsm](docs/fsm.png)

* `IDLE`: line high, waits for `start_tx = '1'`
* `START`: drives `0` for one bit period, then loads first data bit
* `DATA`: outputs 8 bits (LSB first), shifts right each bit period
* `END`: outputs stop level (`1`) for `STOP_BIT` bit periods, asserts `tx_done`

### Bit timing

A simple integer timer generates bit periods, TIMER_LIM is actually BAUD_PERIOD:

$$
TIMER\_LIM=\frac{CLK\_FREQ}{BAUD\_RATE},\qquad
STOP\_LIM= TIMER\_LIM\times STOP\_BIT
$$

No oversampling; the TX side only needs period accuracy.

Key internal signals:

* `timer`: counts `0 .. TIMER_LIM-1`
* `stop_timer`: counts stop-bit clocks
* `shreg(7 downto 0)`: shift register (data)
* `bit_cnt`: `0 .. 7`

---

## Top-level Example (CMOD A7)

`top.vhd` sends an incrementing byte once per **second** (with `CLK_FREQ=12 MHz`), toggling the LED via `tx_done`. Connect `uart_rxd_out` to your USB-UART **RXD**.

Generics used in the example:

* `CLK_FREQ  => 12_000_000`
* `BAUD_RATE => 115_200`
* `STOP_BIT  => 1`

Pinout notes (adapt to your XDC):

* `sysclk` → 12 MHz onboard clock
* `uart_rxd_out` → FTDI **RX** (board-specific)
* `led` → user LED

---

## Testbench

Self-contained testbench (`tb_uart_tx.vhd`) with a 100 MHz clock:

* Sends `0xAB`, waits for the full stop period(s), then sends `0xCD`
* Uses `STOP_BIT = 2` to make the stop interval explicit in waveforms
* Ends simulation with `assert ... "SIM DONE"`

Expected waveform (ModelSim/Questa/XSIM):

![testbench](docs/testbench.png)

---

## Integration Tips

* **Back-to-back bytes**: pulse `start_tx` again any time after `tx_done` returns low (i.e., after `END → IDLE`).
* **Throughput**: with `STOP_BIT=1`, the line is ready for the next start bit immediately after the single stop bit.
* **Glitch-free start**: `start_tx` is only sampled in `IDLE`; pulses during `BUSY` states are ignored.
* **Reset**: the design relies on power-up defaults; add an explicit reset if your toolflow/board requires it.
* **Parity**: not implemented; easiest extension is to insert a `PARITY` state between `DATA` and `END`.

---

## Files

* `uart_tx.vhd` — transmitter RTL
* `top.vhd` — CMOD A7 demo (incrementing byte every second)
* `tb_uart_tx.vhd` — simulation testbench
* `docs/uart_timing.png` — UART frame diagram
* `docs/fsm.png` — state machine
* `docs/testbench.png` — expected sim waveform

---

## Parameters (quick reference)

| Generic     | Meaning                      | Example       |
| ----------- | ---------------------------- | ------------- |
| `CLK_FREQ`  | System clock in Hz           | `100_000_000` |
| `BAUD_RATE` | UART baud                    | `115_200`     |
| `STOP_BIT`  | Number of stop bits (1 or 2) | `1` or `2`    |

---

## Reference Links

1. Mehmet Burak Aykenar – GitHub: `mbaykenar/apis_anatolia`
2. Van Hunter Adams — UART notes: *Universal Asynchronous Receiver Transmitter (UART)*

---

## License

MIT (or match your repo’s license).

---

### Appendix: Bit order sanity check

For a byte `D7..D0`, the serial order on the wire is:

`Start(0) → D0 → D1 → D2 → D3 → D4 → D5 → D6 → D7 → Stop(1...1)`.

`0xAB = 1010_1011₂` therefore transmits `1,1,0,1,0,1,0,1` after the start bit.
