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

## Log Control: Seeing What the Testbench Did

UVVM prints a lot or nothing, depending on which message IDs are enabled. A testbench that only prints a final `SUCCESS` is hard to trust, because you cannot tell whether the checks ran at all.

```vhdl
disable_log_msg(ALL_MESSAGES);   -- silence everything ...
enable_log_msg(ID_LOG_HDR);      -- ... except the headers you log yourself
enable_log_msg(ID_BFM);          -- ... and one line per BFM transaction
log(ID_LOG_HDR, "Test 3: a write to reg0 is ignored", C_SCOPE);
```

`enable_log_msg(ALL_MESSAGES)` is useful while debugging but very verbose. Alerts (`ERROR`, `WARNING`) are always printed, whatever the log settings are.

A passed `check_value` or `await_value` is logged with its own ID, `ID_POS_ACK`. With only `ID_BFM` enabled, BFM transactions show up in the transcript but plain `check_value` checks on pins pass **silently**: a failure would still raise an alert, but a pass leaves no line. Enable `ID_POS_ACK` as well if you want the transcript to prove those checks ran.

## Bus Functional Models (BFMs)

A BFM is a set of procedures that plays one side of a standard interface, so the testbench says *what* should happen and the BFM does *how* the signals move. One call such as `axilite_write(addr, data, msg, ...)` performs a whole AXI4-Lite write: address and data channels, the ready/valid handshakes, and the response check. Doing the same by hand means counting clock cycles for every signal.

[UVVM Light](../viv02_modelsim_setup/README.md) ships a set of BFMs inside the `uvvm_util` library, for example `uart_bfm_pkg`, `axilite_bfm_pkg`, `spi_bfm_pkg`, `i2c_bfm_pkg` and `sbi_bfm_pkg`. The source of each package (`src_bfm/<name>_bfm_pkg.vhd` in the UVVM Light download) is the best documentation: the comment above every procedure says what it does, and the config record lists every setting.

```vhdl
library uvvm_util;
context uvvm_util.uvvm_util_context;
use uvvm_util.axilite_bfm_pkg.all;     -- pick the BFM package for your interface
```

The usage pattern is the same for every BFM:

1. **A config record** holds the BFM's settings (bit time, clock period, timeouts, expected response, ...). Start from `C_<NAME>_BFM_CONFIG_DEFAULT` and set what the default leaves undefined, such as `bit_time` for the UART BFM or `clock_period` for the AXI-Lite BFM.
2. **An interface signal or record** connects the BFM to the DUT ports. For AXI-Lite this is a `t_axilite_if` record. Initialize it before the first call (`init_axilite_if_signals`).
3. **Procedure calls** in the test process. Each one blocks until the transaction is finished.
4. **Local wrapper procedures** hide the arguments that never change (clock, interface signal, scope, config). A procedure with the same name and fewer arguments is declared inside the test process, and VHDL picks the right one by the argument list:

   ```vhdl
   procedure axilite_write (
     constant addr_value : in unsigned;
     constant data_value : in std_logic_vector;
     constant msg        : in string) is
   begin
     axilite_write(addr_value, data_value, msg, clk, axilite_if,
                   C_SCOPE, shared_msg_id_panel, axilite_bfm_config);
   end;
   ```

Worked examples: the UART BFM in [vhd07_uart_tx](../vhd07_uart_tx/README.md) and the AXI-Lite BFM in [z01_custom_AXI4_per](../z01_custom_AXI4_per/README.md).

## Pitfalls That Cost Time

- **A signal assignment does not take effect until the process suspends.** In `data_in <= x"A5"; uart_expect(data_exp => data_in, ...)` the BFM still sees the *previous* value of `data_in`. Pass the value you mean (a constant, a variable, or the expression itself), not a signal you have just assigned. The same applies to BFM config signals: wait a moment (`wait for 1 ns`) after assigning them before the first BFM call, or keep the config in a variable.
- **Do not let a timed assignment land on a clock edge.** A pulse like `start <= '1', '0' after CLK_PERIOD;` that starts exactly on a rising edge ends in the same instant the next edge samples it, and the design can miss it completely. Either assign right after `wait until rising_edge(clk)`, or start the pulse away from the edge (for example after `falling_edge(clk)`), or hold the signal as a level.
- **A completion signal can be a pulse or a level.** Check which one the design gives you before copying a wait from another testbench. `wait until rising_edge(done)` hangs if `done` is already high when you start waiting. A level that stays high during a stop bit needs a wait for its *falling* edge.
- **Never let a testbench hang.** Give every wait a limit:
  - BFM timeouts: `timeout` in the UART config (0 means *never* time out) and `max_wait_cycles` in the AXI-Lite config (1000 by default).
  - `await_value(sig, value, min_time, max_time, ...)` fails instead of waiting forever.
  - `wait until done for 20 us;` plus a check afterwards, as a watchdog around a whole test.
- **A testbench that cannot fail proves nothing.** See the negative test below.

## Making the Testbench Fail on Purpose

Once a test passes, break something deliberately and confirm that it reports an error: change an expected value, or skip a stimulus step. UVVM can also check *for* an error: register how many alerts you expect before the wrong check, and the final summary still says `SUCCESS`.

```vhdl
set_alert_stop_limit(ERROR, 0);                       -- do not stop at the first ERROR
increment_expected_alerts(ERROR, 1, "next check is wrong on purpose");
axilite_check(c_reg2_addr, x"00000000", "WRONG on purpose");   -- raises one ERROR, which was expected
```

Remove the `increment_expected_alerts` line and the same run ends in `Simulation FAILED`. That shows the checks have teeth. The summary table has an `EXPECTED` column next to `REGARDED` for this reason.

## Directed Test Patterns Worth Reusing

Most register-style and FIFO-style designs can be checked with the same handful of tests. [tb_axilite_regs.vhd](../z01_custom_AXI4_per/src/tb_axilite_regs.vhd) uses all of them:

| Pattern | What it finds |
|---|---|
| Reset values | registers that are not reset, or reset to the wrong value |
| Read-only register: write it, read it back | a write that leaks into the register or into a neighbour |
| Write a different value to every register, read all back | wrong address decode, registers that overwrite each other |
| Walking ones (a single `1` through every data bit) | stuck bits, bits shorted to a neighbour, missing bits |
| Partial writes (byte strobes), including none enabled | byte lanes that are ignored or always written |
| Check the real output pin, not only a read-back | a register that stores the value but does not drive the output |
| Overflow and underflow (write more than a FIFO holds, read more than it accepted) | lost, overwritten or repeated data, wrong flags ([vhd18_async_fifo](../vhd18_async_fifo/README.md)) |

## ModelSim Notes

- Compile as **VHDL-2008**. A new project can default to VHDL-2002 and pass `-2002` to `vcom` whatever the global setting says (the project file also stores a language version per file). Set `VHDL93 = 2008` in `modelsim.ini` and/or the per-file or project compile options, and check the `vcom` line in the transcript for `-2008`.
- In project mode the **compile order** is a list in the project. The testbench must compile last, after the DUT. A `Could not find work.<entity>` error on the DUT line, while the DUT files compile fine, almost always means the testbench was compiled first. Fix it under Compile, Compile Order.
- The entity name in the testbench must match the DUT exactly (a name copied from another project is a common cause of the same error).
- Start the simulation from the console (`vsim work.<testbench>`) if the Start Simulation dialog misbehaves.
- The free ModelSim edition slows down for large designs. UVVM alone is large enough for that to be noticeable in long simulations, so keep loops short while developing.

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

## Worked Examples

- [vhd03_debouncer](../vhd03_debouncer/README.md): a complete UVVM testbench (`src/tb_debouncer_uvvm.vhd`), its Makefile, example output, and a note on its own verification coverage. A reference to compare a new testbench against.
- [vhd07_uart_tx](../vhd07_uart_tx/README.md): the UART BFM (`uart_expect`) checking all 256 byte values, and the completion-signal and signal-timing pitfalls above.
- [vhd18_async_fifo](../vhd18_async_fifo/README.md): plain-VHDL smoke tests for a FIFO with two unrelated clocks, including overflow and underflow.
- [z01_custom_AXI4_per](../z01_custom_AXI4_per/README.md): the AXI-Lite BFM driving a custom register slave, from a smoke test to a register-level testbench with a negative test.

---
⬅️ [MAIN PAGE](../README.md)
