# UVVM Verification Guide

How this repo runs self-checking testbenches with UVVM (Universal VHDL Verification Methodology) and GHDL, and how much testbench coverage a design actually needs. Worked example: [vhd03_debouncer](../vhd03_debouncer/README.md).

## Why UVVM

A plain testbench (see `tb_debouncer.vhd` for an example) drives stimulus and leaves you to read the waveform and judge pass/fail by eye. UVVM adds a self-checking layer: `check_value` and `await_value` compare a signal against an expected value, log the result, and count it as an alert. At the end of the run, UVVM reports a single verdict — `Simulation SUCCESS` or `Simulation FAILED` — so you don't have to re-read the waveform every time the design changes.

This guide uses GHDL. For UVVM through Vivado's ModelSim integration instead, see [ModelSim Setup with Vivado](../viv02_modelsim_setup/README.md).

## One-Time Setup

Requires GHDL (VHDL-2008 support) and a clone of [UVVM](https://github.com/UVVM/UVVM), compiled once.

```sh
# Clone UVVM somewhere outside this repo
git clone https://github.com/UVVM/UVVM.git ~/Projects/UVVM

# Compile all UVVM libraries for GHDL into a separate build folder
mkdir -p ~/Projects/uvvm_build
sh ~/Projects/UVVM/script/compile_all.sh ghdl ~/Projects/uvvm_build
```

This produces compiled libraries in `~/Projects/uvvm_build/ghdl`. Every testbench's GHDL commands need `-P~/Projects/uvvm_build/ghdl` to find them.

## Per-Module Setup

Each module with a UVVM testbench gets its own `Makefile` (see `vhd03_debouncer/Makefile` for the working example) and a module-level `.gitignore` for the build output:

```make
UVVM_LIBS := $(HOME)/Projects/uvvm_build/ghdl
GHDL      := ghdl
GHDLFLAGS := --std=08 -frelaxed -fsynopsys -P$(UVVM_LIBS)
TB        := tb_<name>_uvvm
SRC       := src/<design>.vhd src/$(TB).vhd

all: run
analyze: $(SRC)
	$(GHDL) -a $(GHDLFLAGS) $(SRC)
elab: analyze
	$(GHDL) -e $(GHDLFLAGS) $(TB)
run: elab
	$(GHDL) -r $(GHDLFLAGS) $(TB) --vcd=wave.vcd
clean:
	rm -f *.o $(TB) wave.vcd work-obj08.cf UVVM_Alert.txt UVVM_Log.txt build.log
.PHONY: all analyze elab run clean
```

Run with `make`; clean with `make clean`. The Makefile reruns every step on each call — it doesn't track per-file changes — which is fine at this scale.

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

**Trust the result, not just the verdict.** A testbench with no stimulus also reports `SUCCESS` — it just didn't check anything. Confirm the checks you expect actually ran and the waveform shows the stimulus you intended (`wave.vcd`, opened in GTKWave or a similar viewer).

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

Most testbenches in this repo are, and should be, Tier 1 with directed stimulus. Tier 3 is professional/ASIC-team-scale effort, not a bar for a personal FPGA project.

**Formal verification is a different technique, not a deeper tier of simulation.** A solver proves a property holds for *all* reachable states instead of running time-ordered stimulus. The toolchain for it (`sby`/SymbiYosys, `yosys`, `yosys_ghdl`, and solvers like `boolector`/`z3`) comes bundled with oss-cad-suite, if that's ever installed for waveform viewing on this machine, but it's a separate skill from UVVM and isn't covered in this guide.

**What simulation can't catch:** metastability from an asynchronous input (e.g. a physical button) sampled directly into a clocked process. Simulation doesn't model it. The fix is a design pattern — a synchronizer — applied because the input is known to be asynchronous, not a test. See [vhd14_synchronizer](../vhd14_synchronizer/README.md).

## Worked Example

[vhd03_debouncer](../vhd03_debouncer/README.md) has a complete UVVM testbench (`src/tb_debouncer_uvvm.vhd`), its Makefile, example output, and a note on its own verification coverage — a reference to compare a new testbench against.

---
⬅️ [MAIN PAGE](../README.md)
