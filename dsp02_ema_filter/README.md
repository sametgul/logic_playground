# EMA Filter (Single Stage)

A single EMA (exponential moving average) stage is a first-order IIR low-pass: `y[n] = y[n-1] + alpha*(x[n] - y[n-1])`. This is the building block behind the time-constant filter in the SR860/MFLI demodulators — a cascade of these is what later gives the 6/12/18/24 dB/oct slopes.

Float model, fixed-point model, VHDL implementation and a bit-exact verification flow (golden model + compare script) are in place. The file-driven VHDL testbench that closes the loop is the remaining piece.

```
dsp03 stimulus/<name>.txt ─┬─► tb (textio) ──► DUT ──► sim/<name>_actual.txt ─┐
                           └─► gen_expected.py (ema_filter_codes) ───────────►├─► compare.py
                                                 sim/<name>_expected.txt ─────┘
```

## What's here

- `models/ema_float.py` — `alpha_from_tau` (convert a time constant to the per-sample coefficient), `ema_filter` (run the recursion over a sequence), `f3db` (the n-th order -3dB bandwidth formula).
- `models/ema_fixed.py` — two fixed-point models:
  - `ema_filter_fixed` — float-valued, built on `dsp01_fixed_point_basics`'s `qformat.py`, for exploring widths and guard bits. Also has `required_guard_bits`, which sizes the accumulator so a tiny `alpha` doesn't stall the filter (see Gotchas).
  - `ema_filter_codes` (+ `alpha_to_code`) — pure integer arithmetic, the **bit-exact twin of `ema_filter.vhd`**; this is the golden reference for simulation.
- `models/test_ema_float.py`, `models/test_ema_fixed.py` — directed tests (`python test_ema_fixed.py`): step response vs analytic, -3 dB point vs `scipy`, the stall and its guard-bit fix, saturation, round-half-up ties, and that the float and integer models agree bit-for-bit.
- `models/gen_expected.py` — runs a dsp03 stimulus file through `ema_filter_codes` and writes the expected output (one integer code per line).
- `models/compare.py` — diffs expected vs actual; exit code 0 only if every sample is identical.
- `src/ema_filter.vhd` — the implementation (AXI-stream style handshake, synchronous reset, generics `INT_BITS` / `FRAC_BITS` / `GUARD_BITS`).
- `src/tb_ema_filter.vhd` — smoke test: constant step, output checked against the Python value within a tolerance.
- `src/tb_ema_filter_guard_bits.vhd` — the guard-bit scenario in VHDL.
- `notebooks/` — float model vs theory (`ema_exploration.ipynb`) and the stall / guard-bit fix (`ema_fixed_exploration.ipynb`).

## Bit-exact verification flow

Use `python` (needs numpy only for `ema_float`/the tests; the integer model itself is stdlib).

```
cd models

# 1. expected output for a stimulus (prints the alpha code to use in the testbench)
python gen_expected.py ../../dsp03_test_signals/stimulus/sine_10hz.txt \
       -o ../sim/sine_10hz_expected.txt --tau 10e-3 --ts 1e-3

# 2. run the VHDL testbench on the same stimulus -> ../sim/sine_10hz_actual.txt

# 3. compare
python compare.py ../sim/sine_10hz_expected.txt ../sim/sine_10hz_actual.txt
```

Use the same `--int-bits/--frac-bits/--guard-bits` as the DUT generics (defaults 2/15/0 match `tb_ema_filter`), and the same alpha code in both places. `sim/` is git-ignored.

## Rounding: why half-up

The VHDL rounds with `round_shift`: add half an LSB, then arithmetic-shift right. A shift on a two's-complement number is a floor, so the whole operation is `floor(x + 0.5)` — **round half up** (ties toward +∞). The Python models used to round half **away from zero** (`-2.5 → -3`), which gives the same answer except on *negative exact ties* (`-2.5 → -2` in hardware). Those ties are not rare in a feedback filter — `alpha * diff` often lands on exactly half an LSB — so a bit-exact comparison on signed signals would have mismatched constantly.

Two ways to close the gap: make the VHDL do round-half-away (needs sign-dependent logic: a conditional add, or an extra compare, on a path that is otherwise one adder) or make the model match the hardware. Half-up costs nothing in hardware, and the bias it introduces is a fraction of an LSB, far below anything this filter resolves (guard bits push the accumulator's rounding error well under the output LSB). So the model was changed: `qformat.to_int` gained `round_mode="half_up"`, and `ema_filter_fixed` defaults to it. The model must follow the hardware here, not the other way round — the golden model's job is to describe what the silicon does.

## Gotchas

**Tiny alpha stalls the accumulator.** A long time constant at a high sample rate makes `alpha` tiny, and that breaks the fixed-point accumulator in two stages, not one: first the filter can fail to move at all (the very first increment underflows to zero), and even once it's moving, it can still stall partway through convergence instead of reaching the true final value, because `alpha * diff` keeps shrinking as `diff` does. `required_guard_bits` sizes the accumulator for the second, subtler failure — enough guard bits that the residual stall point lands within one output LSB, not just enough to get it moving initially.

**The float model is not bit-exact at wide formats.** At the VHDL defaults (Q3.21 + 20 guard bits) `diff * alpha` is ~84 bits, past float64's 53-bit mantissa, so `ema_filter_fixed` silently rounds intermediates. Use `ema_filter_codes` for bit-exact work.

**Known VHDL edge case: `diff` can overflow.** `ema_filter.vhd` computes `diff := x_aligned - y_acc_r` in `ACC_WIDTH` bits with a plain `-`. Both operands are in range, but their difference can be up to twice the range, so a large swing (e.g. input at +rail while the output sits near −rail) wraps. The golden model uses ideal arithmetic and `gen_expected.py` prints a warning with the count when this happens in a given stimulus; none of the standard dsp03 signals trigger it. Fix when it matters: compute `diff` in `ACC_WIDTH + 1` bits (the product width already has room).

## Open question

The notebooks use placeholder values for sample period and time constant. Real bit widths depend on knowing the actual ADC sample rate and the range of time constants used in the lab — not yet answered.
