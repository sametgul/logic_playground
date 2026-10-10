# UVVM Verification Guide

How this repo runs self-checking testbenches with UVVM (Universal VHDL Verification Methodology), and how much testbench coverage a design actually needs. For UVVM through Vivado's ModelSim integration, see [ModelSim Setup with Vivado](../viv02_modelsim_setup/README.md).

## Testbench Skeleton

```vhdl
library uvvm_util;
context uvvm_util.uvvm_util_context;

-- in the architecture:
signal clock_ena : boolean := false;
clock_generator(clk, clock_ena, C_CLK_PERIOD, "<label>");

-- in the test process:
clock_ena <= true;
-- ... stimulus and checks ...
report_alert_counters(FINAL);
std.env.stop;
wait;
```

## Checking Values: `check_value` vs `await_value`

`check_value` takes no time — it samples a signal the instant it's called. Use it after a `wait for` when you know exactly when the signal should already have settled:

```vhdl
wait for 2 ms;
check_value(sig_out, '1', ERROR, "Output idle high after startup", C_SCOPE);
```

`await_value` waits for you. It suspends until the signal reaches the expected value, and fails if that happens too early or not at all within the window:

```vhdl
sig_in <= '0';
await_value(sig_out, '0', 4 ms, 7 ms, ERROR, "Press debounced within window", C_SCOPE);
```

Use `await_value` when you're checking that a transition happens within a timing window. Use `wait` + `check_value` when you're confirming a signal has *not* changed (e.g. rejecting a glitch) — `await_value` isn't suited to "confirm nothing happened."

## Reading the Output

```
UVVM: ID_POS_ACK   9000000.0 ns  TB seq.   check_value(sl, 1) => OK. Value was 1. '3 ms glitch rejected'
...
UVVM:      >> Simulation SUCCESS: No mismatch between counted and expected serious alerts
```

- `ID_POS_ACK ... => OK`: a check passed. `=> Failed` shows the expected and actual values.
- The final summary table counts alerts by level; any nonzero `REGARDED` count in `ERROR`/`WARNING`/`FAILURE` means something's wrong.
- The last line is the verdict: `Simulation SUCCESS` or `Simulation FAILED`.
- UVVM stops the run after the first `ERROR` by default (`STOP_LIMIT`). To see every failure in one run instead of just the first, raise the limit at the top of the test process: `set_alert_stop_limit(ERROR, 0);`.

## How Much to Test: Verification Tiers

Not every design needs the same depth of testing. Scale it by: *What happens if this is wrong? How complex is the design? Will this be reused?*

**Tier 1 — almost everything, including hobby projects:**
- Reset/startup behavior
- Normal operation (happy path)
- The corner cases that come directly from the spec (e.g. a debounce time boundary)

**Tier 2 — once a design has more than one FSM, a bus, or external timing dependencies:**
- Timing edge cases (event exactly at a clock edge or exactly at a limit)
- Simultaneous/conflicting events
- A few directed illegal-input cases

**Tier 3 — complex, safety-critical, or widely-reused IP:**
- Randomized/stress testing (UVVM's `RandomPkg`)
- Coverage tracking
- A full regression suite
- Formal verification (a separate discipline — see note below) for critical invariants

Most testbenches in this repo are Tier 1 with directed stimulus. Tier 3 is professional/ASIC-team-scale effort, not a bar for a personal FPGA project.

## Worked Example

[vhd03_debouncer](../vhd03_debouncer/README.md) has a complete UVVM testbench (`src/tb_debouncer_uvvm.vhd`), its Makefile, example output, and a note on its own verification coverage — a reference to compare a new testbench against.

---
⬅️ [MAIN PAGE](../README.md)
