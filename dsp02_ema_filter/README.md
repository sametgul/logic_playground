# EMA Filter (Single Stage)

A single EMA (exponential moving average) stage is a first-order IIR low-pass: `y[n] = y[n-1] + alpha*(x[n] - y[n-1])`. This is the building block behind the time-constant filter in the SR860/MFLI demodulators — a cascade of these is what later gives the 6/12/18/24 dB/oct slopes.

Float model and fixed-point model are both done — no VHDL yet.

## What's here

- `models/ema_float.py` — `alpha_from_tau` (convert a time constant to the per-sample coefficient), `ema_filter` (run the recursion over a sequence), `f3db` (the n-th order -3dB bandwidth formula).
- `models/test_ema_float.py` — directed tests (`python3 test_ema_float.py`): step response checked against the analytic `1 - exp(-t/tau)`, and the -3dB point checked against `scipy.signal.freqz`.
- `models/ema_fixed.py` — the same recursion built on `dsp01_fixed_point_basics`'s `qformat.py`, at an explicit `Q(int_bits).(frac_bits)` width. Also has `required_guard_bits`, which sizes the accumulator wide enough that a tiny `alpha` doesn't stall the filter (see Gotchas below).
- `models/test_ema_fixed.py` — directed tests (`python3 test_ema_fixed.py`), including the exact stall scenario from the top-level CLAUDE.md's hardware note and the guard-bit fix for it.
- `notebooks/ema_exploration.ipynb` — plots the float model's step response and frequency response against theory, plus a two-tone (10 Hz / 100 Hz) demo of what a single stage can and can't separate.
- `notebooks/ema_fixed_exploration.ipynb` — plots the stall and the guard-bit fix.

## Gotchas

A long time constant at a high sample rate makes `alpha` tiny, and that breaks the fixed-point accumulator in two stages, not one: first the filter can fail to move at all (the very first increment underflows to zero), and even once it's moving, it can still stall partway through convergence instead of reaching the true final value, because `alpha * diff` keeps shrinking as `diff` does. `required_guard_bits` sizes the accumulator for the second, subtler failure — enough guard bits that the residual stall point lands within one output LSB, not just enough to get it moving initially.

## Open question

The notebooks use placeholder values for sample period and time constant. Real bit widths depend on knowing the actual ADC sample rate and the range of time constants used in the lab — not yet answered.
