# UART Transmitter

A minimal, synthesizable UART **TX** for FPGA boards (tested on **CMOD A7**) and a clean testbench. The design is **8-N-1 or 8-N-2** selectable via generic (8 data bits, no parity, 1 or 2 stop bits), LSB-first, idle level high.

Note: unlike the [Debouncer](../vhd03_debouncer/README.md) which separates the FSM and timer into two processes, this design combines both into a single clocked process — the timer drives state transitions directly.

---

## Source Files

| File                      | Description                                             |
|---------------------------|---------------------------------------------------------|
| `src/uart_tx.vhd`         | Core UART TX FSM — parametric, 4-state                  |
| `src/tb_uart_tx.vhd`      | Testbench — sends 0xAB then 0xCD, self-terminating      |
| `src/tb_uart_tx_uvvm.vhd` | UVVM testbench — sends all 256 byte values, self-checking with the UVVM UART BFM |
| `src/top_uart_tx.vhd`     | Top level — sends incrementing byte once per second     |
| `src/top_uart_tx_btn.vhd` | Top level — sends 3 sequential bytes on button press    |

---

## Features

* **Parametric** clock, baud rate, and stop bit count via `CLK_FREQ`, `BAUD_RATE`, `STOP_BIT` generics
* **One-byte shifter** (no FIFO) — `start_tx` is sampled only in `s_IDLE`, pulses during busy states are ignored
* **Status output** `tx_done` asserted at the entry of `s_END`, held high for the stop bit period(s)
* Compact 4-state FSM: `s_IDLE → s_START → s_DATA → s_END → s_IDLE`

---

## UART Frame

Idle line is `'1'`. A frame is:

* **Start bit**: `'0'` for one bit period
* **8 data bits**: LSB first
* **STOP_BIT** stop bits: `'1'`

![timing](docs/uart_timing.png)

---

## Architecture

### State Machine

![fsm](docs/fsm.png)

* `s_IDLE`: line high, waits for `start_tx = '1'`, latches `data_in` into shift register
* `s_START`: drives `'0'` for one bit period
* `s_DATA`: outputs 8 bits LSB-first, shifts right each bit period, `bit_cnt` tracks position
* `s_END`: outputs `'1'` for `STOP_BIT` bit periods, asserts `tx_done`

### Bit Timing

A simple integer timer generates bit periods:

$$
TIMER\_LIM=\frac{CLK\_FREQ}{BAUD\_RATE},\qquad
STOP\_LIM= TIMER\_LIM \times STOP\_BIT
$$

No oversampling — the TX side only needs period accuracy.

Key internal signals:

| Signal       | Description                       |
|--------------|-----------------------------------|
| `timer`      | counts `0 .. TIMER_LIM-1`         |
| `stop_timer` | counts stop-bit clocks            |
| `shreg`      | 8-bit shift register (data)       |
| `bit_cnt`    | bit position counter, `0 .. 7`    |

---

## Top Level 1 — Auto Transmit (`top_uart_tx.vhd`)

Sends an incrementing byte once per second (`CLK_FREQ = 12 MHz`). No button needed — useful for verifying the UART link is alive. `cnt` increments every second and wraps naturally at 255 back to 0. The onboard LED reflects `tx_done`.

Generics used:

* `CLK_FREQ  => 12_000_000`
* `BAUD_RATE => 115_200`
* `STOP_BIT  => 1`

Pinout (adapt to your XDC):

* `sysclk` → 12 MHz onboard clock
* `uart_rxd_out` → FTDI RX pin
* `led` → user LED

---

## Top Level 2 — Button Triggered (`top_uart_tx_btn.vhd`)

Sends 3 sequential bytes (`0x01, 0x02, 0x03`) on each button press, then returns to idle. Uses a 3-state FSM (`IDLE → DATA → sWAIT`) with edge detection on the button and falling-edge detection on `tx_done` to sequence the transfers.

Key design points:

* `cnt` resets to 0 in `IDLE` — each button press always sends the same sequence
* `datain <= std_logic_vector(cnt + 1)` uses an expression (not a signal read) to correctly capture the incremented value in the same cycle `start_tx` fires — see [pre-assignment note in Debouncer](../vhd03_debouncer/README.md#pre-assigning-signals-before-a-state-transition)
* `tx_done` falling edge detection (`tx_done_prev = '1' and tx_done_r = '0'`) triggers the next byte — fires after the stop bit period completes and `uart_tx` has returned to `s_IDLE`

Additional pinout vs Top Level 1:

* `btn` → onboard button (active high, no debounce needed at this baud rate)

---

## Testbench (`tb_uart_tx.vhd`)

Self-contained testbench with a 100 MHz clock:

* Sends `0xAB` (10101011) — alternating bits, good for scope verification
* Waits for full stop period, then sends `0xCD` (11001101) — verifies back-to-back transfers
* Uses `STOP_BIT = 2` to make the stop interval clearly visible in waveforms
* Ends with `assert false report "SIM DONE" severity failure`

Expected waveform:

![testbench](docs/testbench.png)

---

## UVVM Testbench (`tb_uart_tx_uvvm.vhd`)

Self-checking version of the testbench, using the UART BFM that ships in [UVVM Light](../viv02_modelsim_setup/README.md) (`uvvm_util.uart_bfm_pkg`). For each value `0..255` it starts a transmission, lets `uart_expect` sample `tx_out` as a UART receiver would, and compares the decoded byte with the one sent.

```vhdl
data_in  <= std_logic_vector(to_unsigned(i, 8));
start_tx <= '1';
uart_expect(data_exp => std_logic_vector(to_unsigned(i, 8)), msg => "byte",
            rx => tx_out, terminate_loop => terminate_loop,
            config => uart_bfm_config, scope => C_SCOPE);
wait for CLK_PERIOD;
start_tx <= '0';
await_value(tx_done, '0', 0 ns, BIT_TIME, ERROR, "tx_done low after stop bit", C_SCOPE);
```

Points worth knowing:

* **Bit time**: `BIT_TIME = 868 * CLK_PERIOD` (8680 ns), not `1 / 115200`. The DUT divides `CLK_FREQ / BAUD_RATE` as an integer, so the BFM has to use the same 868 clocks.
* **`start_tx` is held high** while the BFM receives, then dropped. The DUT only looks at `start_tx` in `s_IDLE`, and `uart_expect` returns in the middle of the stop bit, half a bit before the DUT is idle again. So `start_tx` is low again before the next byte can start and no second frame is triggered.
* **`data_exp` is built from `i`, not `data_in`**: `data_in` is a signal and still holds the previous byte when `uart_expect` is called in the same delta.
* **`tx_done` is a level, not a pulse**: it rises when the stop bit starts, which is before `uart_expect` returns. Waiting for its rising edge would hang, so the loop waits for it to fall (`await_value`), which marks the end of the frame and gives a time limit as well.
* **Finite timeout**: `uart_bfm_config.timeout` is `20 * BIT_TIME`. A value of 0 means "never time out", which turns a dead DUT into a hung simulation.

### Running it (ModelSim)

* Compile `uart_tx.vhd`, then the testbench, as **VHDL-2008**. `vcom -2008` is needed for `context` and `std.env`.
* `uvvm_util` must be mapped to the compiled UVVM Light library.
* Start with `vsim work.tb_uart_tx_uvvm`, then `run -all`. The full 256 bytes take about 22 ms of simulated time, so the free ModelSim edition is slow here.

Example output (first byte, `STOP_BIT = 1`):

```
UVVM: ID_BFM_WAIT       100.0 ns  TB seq.  Expecting data x"00" within 1 occurrences and 173600 ns. byte
UVVM: ID_BFM          82560.0 ns  TB seq.  uart_expect(x"00")=> OK, received data = x"00" after 1 occurrences and 82460 ns. 'byte'
UVVM: ID_POS_ACK      86900.0 ns  TB seq.  await_value(sl, 0, 0 ns, 8680 ns) => OK. Condition occurred after 4330 ns. 'tx_done low after stop bit'
```

`uart_expect` returns 82.46 µs after the start bit, 9.5 bit times in, in the middle of the stop bit. `tx_done` falls half a bit later.

### Verification Coverage

Covers the happy path: all 256 data values, LSB-first bit order, start and stop bit levels as seen by a receiver, and `tx_done` going low at the end of every frame.

Not covered yet: exact start and stop bit widths (the BFM samples mid-bit, so a bit that is a few clocks too long or short still passes), `start_tx` pulses during a busy frame, back-to-back frames with no idle gap, `start_tx` held high, and `STOP_BIT = 2`.

---

## Integration Tips

* **Back-to-back bytes**: pulse `start_tx` again any time after `tx_done` goes low (after `s_END → s_IDLE` transition)
* **Glitch-free start**: `start_tx` is only sampled in `s_IDLE` — pulses during busy states are safely ignored
* **Reset**: design relies on power-up defaults — add an explicit synchronous reset if your toolflow requires it
* **Parity**: not implemented — easiest extension is to insert a `PARITY` state between `s_DATA` and `s_END`

---

## References

1. [Mehmet Burak Aykenar - Github](https://github.com/mbaykenar/apis_anatolia)

---
⬅️ [MAIN PAGE](../README.md) | ⬅️ [Percentage-Based PWM](../vhd06_pwm_percent/README.md) | ➡️ [UART Receiver](../vhd08_uart_rx/README.md)
