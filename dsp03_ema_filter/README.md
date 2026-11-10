# EMA Filter (Single Stage)

Part 3 of the DSP series: uses the Q-format helper from [dsp01](../dsp01_fixed_point_basics/README.md) and the stimulus files from [dsp02](../dsp02_test_signals/README.md).

A single EMA (exponential moving average) stage is a first-order IIR low-pass: $$y[n] = y[n-1] + \alpha(x[n] - y[n-1]).$$ This is the building block behind the time-constant filter in the SR860/MFLI demodulators — a cascade of these is what later gives the 6/12/18/24 dB/oct slopes.

Float model, fixed-point model, VHDL implementation and a bit-exact verification flow (golden model + compare script) are in place. The file-driven VHDL testbench that closes the loop is the remaining piece.

```
dsp02 stimulus/<name>.txt ─┬─► tb (textio) ──► DUT ──► sim/<name>_actual.txt ─┐
                           └─► gen_expected.py (ema_filter_codes) ───────────►├─► compare.py
                                                 sim/<name>_expected.txt ─────┘
```

## How to work through this folder

The folder is a ladder: each step reuses the previous one and adds exactly one new idea. Go in this order, and do not move on until you can answer the "check yourself" questions without looking.

**Before you start (15 min).** Skim the two earlier notebooks for the vocabulary you will use: [dsp01 Q-format notebook](../dsp01_fixed_point_basics/notebooks/qformat_exploration.ipynb) (codes, saturation, rounding modes, *ties*) and [dsp02 test signals notebook](../dsp02_test_signals/notebooks/generate_signals.ipynb) (tone, dB, bins, aliasing). Everything below assumes them.

### Step 1. The filter itself, in floats (the theory)

- **Read:** the formula at the top of this README, then [ema_float.py](models/ema_float.py) (about 25 lines).
- **Run:** [ema_exploration.ipynb](notebooks/ema_exploration.ipynb), and `python3 test_ema_float.py` in `models/`.
- **Check yourself:**
  - What does $\alpha$ mean, and why is $\alpha = 1 - e^{-T_s/\tau}$ and not simply $T_s/\tau$?
  - Why does the step response follow $1 - e^{-t/\tau}$, and how many $\tau$ until it is within 1% (answer: about 4.6)?
  - Where is the -3 dB point of one stage, and why does a single stage not separate 10 Hz from 100 Hz cleanly? (The notebook's two-tone table is the answer.)

### Step 2. The same filter in fixed point, and how it breaks

- **Read:** [ema_fixed.py](models/ema_fixed.py), `ema_filter_fixed` and `required_guard_bits` only (skip the integer model for now).
- **Run:** [ema_fixed_exploration.ipynb](notebooks/ema_fixed_exploration.ipynb), and `python3 test_ema_fixed.py`.
- **Predict before you run:** with $\tau = 1\ \text{s}$ at 1 MSa/s, what does the output do with no guard bits? (It never leaves 0.) Then with the guard bits `required_guard_bits` returns?
- **Check yourself:**
  - Why does `alpha * diff` round to zero even though `alpha` itself is not zero? (Two stages: the first increment underflows; later `diff` shrinks until it underflows again.)
  - What is a guard bit, and why do they go in the *accumulator* and not in the input/output word?

### Step 3. The integer model (the golden reference)

- **Read:** `ema_filter_codes`, `_round_shift`, `_saturate` at the bottom of [ema_fixed.py](models/ema_fixed.py), and the [Rounding: why half-up](#rounding-why-half-up) section below.
- **Run:** `python3 gen_expected.py ../../dsp02_test_signals/stimulus/step.txt -o ../sim/step_expected.txt --tau 10e-3 --ts 1e-3` and open the output next to the stimulus.
- **Check yourself:**
  - Why is the integer model needed when the float-based one already exists? (53-bit mantissa vs the ~84-bit product.)
  - Why is `>>` on a negative Python integer the same operation as `shift_right` on VHDL `signed`? And what does that make "add half, then shift"? (A round-half-up.)
  - Work one sample by hand: `x = 32768`, `y = 0`, `alpha_code = 3118`, no guard bits. What are `diff`, `product`, `increment`, `y`? (Answer: 32768, 102,170,624, 3118, 3118.)

### Step 4. The VHDL

Read [ema_filter.vhd](src/ema_filter.vhd) in this order, always with `ema_filter_codes` open next to it. The VHDL is the same algorithm line for line.

1. **Generics and widths first:** `DATA_WIDTH`, `ACC_FRAC_BITS`, `ACC_WIDTH`, `PRODUCT_WIDTH`. Draw the three words (input, accumulator, product) as boxes with the binary point marked.
2. **The helper functions:** `saturate_resize`, `saturate_add`, `round_shift`. Each one has a one-line Python twin (`_saturate`, `_round_shift`).
3. **The process:** the six statements inside `elsif s_axis_tvalid = '1' and s_axis_tready = '1'` are the six lines of the Python loop.
4. **The handshake:** `s_axis_tready <= (not out_valid_r) or m_axis_tready;`. When can the filter accept a sample, and what happens if the consumer stalls?
- **Then read the testbenches:** [tb_ema_filter.vhd](src/tb_ema_filter.vhd) (the smoke test: constant step, one number to check) and [tb_ema_filter_guard_bits.vhd](src/tb_ema_filter_guard_bits.vhd) (the stall, in hardware).
- **Check yourself:** why does the smoke test need a `TOLERANCE`, and why will the file-driven test in Step 5 not need one?

### Step 5. Bit-exact verification (your testbench)

This is the step you write yourself: a file-driven testbench that reads a dsp02 stimulus `.txt`, feeds it through the AXI-stream port, and writes `sim/<name>_actual.txt`. Follow the guide at [Bit-exact verification flow](#bit-exact-verification-flow) below, then `compare.py` has to print `PASS: 2048 samples bit-exact` for every file in the standard set.

Do the files in this order, easiest first: `step`, `impulse`, `sine_10hz`, `noisy_sine_10hz`, `compound_10_100hz`, `chirp_1_200hz`. A failure on the first one is a plumbing bug (off-by-one in the capture, wrong alpha code); a failure only on the noisy or negative-going signals points at rounding or sign handling.

### Step 6. Break it on purpose, then fix it

The [Known VHDL edge case](#gotchas) (`diff` overflow) is a real bug that the standard set does not trigger. Make it trigger:

1. In the dsp02 notebook add `"square_1p5": square(5, 1.5, n=N, fs=FS)` to `signals` and run it. The file lands in `../stimulus_custom/square_1p5.txt`. When the square flips from +1.5 to -1.5 the output is still near +1.5, so `diff = x - y` is about -3.0, but `diff` is stored in the same range as the accumulator, [-2, 2). It wraps. Run `gen_expected.py` on that file with the usual `--tau 10e-3 --ts 1e-3` and it warns about 100 such samples. (Amplitude 1.0 gives 0 and 1.9 gives 140, which is why the standard set never showed it.)
2. Run your testbench and `compare.py`: it must fail, and the first mismatch should be at the first edge, around sample 100.
3. Fix the VHDL (compute `diff` in `ACC_WIDTH + 1` bits), run again, and `compare.py` must pass.

This is the whole point of the flow: the golden model and a nasty stimulus found a real bug that "it looks right in the waveform" would not have.

### Step 7. Where this goes next

The Open question at the bottom (real sample rate and time constants) decides the final bit widths. After that the cascade of stages (6/12/18/24 dB/oct) and the demodulator build on exactly this block, so keep the verification flow: any new block gets a golden model first, then a file-driven testbench.

## What's here

- `models/ema_float.py` — `alpha_from_tau` (_convert a time constant to the per-sample coefficient_), `ema_filter` (_run the recursion over a sequence_), `f3db` (_the n-th order -3dB bandwidth formula_).
- `models/ema_fixed.py` — two fixed-point models:
  - `ema_filter_fixed` — float-valued, built on `dsp01_fixed_point_basics`'s `qformat.py`, for exploring widths and guard bits. Also has `required_guard_bits`, which sizes the accumulator so a tiny `alpha` doesn't stall the filter (see Gotchas).
  - `ema_filter_codes` (+ `alpha_to_code`) — pure integer arithmetic, the **bit-exact twin of `ema_filter.vhd`**; this is the golden reference for simulation.
- `models/test_ema_float.py`, `models/test_ema_fixed.py` — directed tests (`python test_ema_fixed.py`): step response vs analytic, -3 dB point vs `scipy`, the stall and its guard-bit fix, saturation, round-half-up ties, and that the float and integer models agree bit-for-bit.
- `models/gen_expected.py` — runs a dsp02 stimulus file through `ema_filter_codes` and writes the expected output (one integer code per line).
- `models/compare.py` — diffs expected vs actual; exit code 0 only if every sample is identical.
- `src/ema_filter.vhd` — the implementation (AXI-stream style handshake, synchronous reset, generics `INT_BITS` / `FRAC_BITS` / `GUARD_BITS`).
- `src/tb_ema_filter.vhd` — smoke test: constant step, output checked against the Python value within a tolerance.
- `src/tb_ema_filter_guard_bits.vhd` — the guard-bit scenario in VHDL.
- `notebooks/` — float model vs theory (`ema_exploration.ipynb`) and the stall / guard-bit fix (`ema_fixed_exploration.ipynb`). Both are also available in Turkish (Türkçe sürüm): `ema_exploration_tr.ipynb` and `ema_fixed_exploration_tr.ipynb`.

## Bit-exact verification flow

Use `python` (needs numpy only for `ema_float`/the tests; the integer model itself is stdlib).

```
cd models

# 1. expected output for a stimulus (prints the alpha code to use in the testbench)
python gen_expected.py ../../dsp02_test_signals/stimulus/sine_10hz.txt \
       -o ../sim/sine_10hz_expected.txt --tau 10e-3 --ts 1e-3

# 2. run the VHDL testbench on the same stimulus -> ../sim/sine_10hz_actual.txt

# 3. compare
python compare.py ../sim/sine_10hz_expected.txt ../sim/sine_10hz_actual.txt
```

Use the same `--int-bits/--frac-bits/--guard-bits` as the DUT generics (defaults 2/15/0 match `tb_ema_filter`), and the same alpha code in both places. `sim/` is git-ignored.

## Rounding: why half-up

The VHDL rounds with `round_shift`: add half an LSB, then arithmetic-shift right. A shift on a two's-complement number is a floor, so the whole operation is $\lfloor x + 0.5 \rfloor$ — **round half up** (ties toward +∞). The Python models used to round half **away from zero** ($-2.5 \to -3$), which gives the same answer except on *negative exact ties* ($-2.5 \to -2$ in hardware). Those ties are not rare in a feedback filter — `alpha * diff` often lands on exactly half an LSB — so a bit-exact comparison on signed signals would have mismatched constantly.

Two ways to close the gap: make the VHDL do round-half-away (needs sign-dependent logic: a conditional add, or an extra compare, on a path that is otherwise one adder) or make the model match the hardware. Half-up costs nothing in hardware, and the bias it introduces is a fraction of an LSB, far below anything this filter resolves (guard bits push the accumulator's rounding error well under the output LSB). So the model was changed: `qformat.to_int` gained `round_mode="half_up"`, and `ema_filter_fixed` defaults to it. The model must follow the hardware here, not the other way round — the golden model's job is to describe what the silicon does.

## Gotchas

**Tiny alpha stalls the accumulator.** A long time constant at a high sample rate makes `alpha` tiny, and that breaks the fixed-point accumulator in two stages, not one: first the filter can fail to move at all (the very first increment underflows to zero), and even once it's moving, it can still stall partway through convergence instead of reaching the true final value, because `alpha * diff` keeps shrinking as `diff` does. `required_guard_bits` sizes the accumulator for the second, subtler failure — enough guard bits that the residual stall point lands within one output LSB, not just enough to get it moving initially.

**The float model is not bit-exact at wide formats.** At the VHDL defaults (Q3.21 + 20 guard bits) `diff * alpha` is ~84 bits, past float64's 53-bit mantissa, so `ema_filter_fixed` silently rounds intermediates. Use `ema_filter_codes` for bit-exact work.

**Known VHDL edge case: `diff` can overflow.** `ema_filter.vhd` computes `diff := x_aligned - y_acc_r` in `ACC_WIDTH` bits with a plain `-`. Both operands are in range, but their difference can be up to twice the range, so a large swing (e.g. input at +rail while the output sits near −rail) wraps. The golden model uses ideal arithmetic and `gen_expected.py` prints a warning with the count when this happens in a given stimulus; none of the standard dsp02 signals trigger it. Fix when it matters: compute `diff` in `ACC_WIDTH + 1` bits (the product width already has room).

## Open question

The notebooks use placeholder values for sample period and time constant. Real bit widths depend on knowing the actual ADC sample rate and the range of time constants used in the lab — not yet answered.
