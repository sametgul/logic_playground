# Fixed-Point Basics (Q-Format Helpers)

Before writing a fixed-point filter, you need a way to answer two questions: what value does a given bit pattern actually represent, and what happens when a value doesn't fit? This folder is a small Q-format helper for prototyping fixed-point math in Python before touching VHDL.

## What's here

- `models/qformat.py` — the reusable helper: `to_int`, `from_int`, `saturate`, `quantize`. Other blocks import this directly.
- `models/test_qformat.py` — directed regression tests (`python3 test_qformat.py`), covering rounding ties, truncation, round-trip, and saturation.
- `notebooks/qformat_exploration.ipynb` — walks through what Q-format means and demonstrates each function interactively, including why rounding defaults to round-half-away-from-zero instead of truncation.

Start with the notebook for the explanation; read `qformat.py` directly if you just want the code.
