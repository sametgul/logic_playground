# Fixed-Point Basics (Q-Format Helpers)

Before writing a fixed-point filter, you need a way to answer two questions: what value does a given bit pattern actually represent, and what happens when a value doesn't fit? This folder is a small Q-format helper for prototyping fixed-point math in Python before touching VHDL.

Part 1 of the DSP series: the Q-format helper is imported by [dsp02 test signals](../dsp02_test_signals/README.md) (to quantize stimulus) and [dsp03 EMA filter](../dsp03_ema_filter/README.md) (fixed-point model).

## What's here

- `models/qformat.py` — the reusable helper: `to_int`, `from_int`, `saturate`, `quantize`. Other blocks import this directly.
- `models/test_qformat.py` — directed regression tests (`python3 test_qformat.py`), covering rounding ties (_including the `half_up` mode that matches hardware add-half-then-shift rounding, see `dsp03_ema_filter/README.md`_), truncation, round-trip, and saturation.
- `notebooks/qformat_exploration.ipynb` — walks through what Q-format means and demonstrates each function interactively, including the three rounding modes (`truncate`, `nearest`, `half_up`), how their bias differs, why exact ties are common in hardware, and which mode to use when matching VHDL.

Start with the notebook for the explanation; read `qformat.py` directly if you just want the code.
