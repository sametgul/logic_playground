# CDC Synchronizer + Synchronized UART Receiver

A generic multi-flip-flop **synchronizer** for crossing an asynchronous single-bit signal into a clock domain, plus a **UART RX** core wrapped behind it (`uart_rx_synched`) as a worked example of CDC applied to a real asynchronous input.

---

## Source Files

| File | Description |
|------|-------------|
| `src/synchronizer.vhd` | Generic `N`-stage synchronizer (default N=3), `ASYNC_REG` attribute set |
| `src/uart_rx.vhd` | UART RX core — mid-bit sampling, 4-state FSM |
| `src/uart_rx_synched.vhd` | Top level — instantiates `synchronizer` in front of `uart_rx` |
| `src/tb_uart_rx_synched.vhd` | Testbench — drives a UART frame into `rx_in`, observes `data_out`/`read_done` |

---

## Why Synchronize `rx_in`?

A flip-flop needs its `D` input to hold steady for a small window around the clock edge — setup time before the edge, hold time after it. `rx_in` comes from an external UART line, so it changes asynchronously with respect to `clk` and doesn't know or care about that window. If it changes *inside* the window, the flop's output can hang briefly at an invalid voltage between `'0'` and `'1'` before settling to one or the other — that unresolved state is **metastability**. It usually resolves within a fraction of a clock cycle, but if it hasn't resolved by the time downstream logic reads it, different gates can interpret the still-settling voltage differently, corrupting the design's state.

The fix isn't to prevent metastability (you can't — any circuit sampling an async signal can hit it) but to give it time to resolve before the value is used. Passing `rx_in` through `N` flip-flops first does exactly that: even if the first flop goes metastable, it almost always resolves to a clean `'0'` or `'1'` well within one clock period, so the second flop samples a settled value; each additional stage is extra insurance against the rare case where resolution takes longer. `ASYNC_REG` marks these flops so placement/timing tools keep them close together and don't try to time or optimize the (inherently asynchronous, unanalyzable) first-stage capture like ordinary logic.

```
rx_in ──► [FF]─►[FF]─►[FF] ──► sync_out ──► uart_rx.rx_in
           N-stage synchronizer
```

`data_o` is tapped combinationally off the last flip-flop (`sync_ff'left`), so total latency is exactly **N** cycles.

![synchronizer waveform, N=3: async_in propagating through sync_ff to sync_out over 3 cycles](docs/synchronizer_waveform.png)

---

## Ports (`uart_rx_synched`)

| Port | Direction | Description |
|------|-----------|-------------|
| `clk` | in | System clock |
| `rx_in` | in | Asynchronous serial input, idle high |
| `data_out[7:0]` | out | Received byte, stable while `read_done = '1'` |
| `read_done` | out | One-cycle pulse at end of valid frame |

Generics: `CLK_FREQ`, `BAUD_RATE` (passed through to `uart_rx`), `N` (synchronizer depth, passed to `synchronizer`).

---

## Relation to [vhd08_uart_rx](../vhd08_uart_rx/README.md)

`src/uart_rx.vhd` here is the same core as `vhd08_uart_rx/src/uart_rx.vhd` (differs only in formatting). Neither version re-checks `rx_in` at the T/2 point before committing to the start bit, nor validates the stop bit before asserting `read_done` — both are lean, single-sample cores with no glitch rejection or framing-error detection. Worth adding those checks to both if used on a noisy or unverified line.

---

## Testbench (`tb_uart_rx_synched.vhd`)

Drives a clean UART frame (`0xAB` at 115200 Bd / 100 MHz) into `rx_in` and instantiates `uart_rx_synched` as the DUT, exercising the synchronizer and RX core together end-to-end.

## References

1. [Mehmet Burak Aykenar – GitHub](https://github.com/mbaykenar/apis_anatolia)

---

⬅️ [MAIN PAGE](../README.md) | ⬅️ [SPI Master — With CS/Idle Timing](../vhd12_cs_timing/README.md)
