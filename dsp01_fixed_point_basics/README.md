# Fixed-Point Basics (Q-Format Helpers)

Before writing a fixed-point filter, you need a way to answer two questions:
what value does a given bit pattern actually represent, and what happens
when a value doesn't fit? This folder is just that — a small Q-format
helper for prototyping fixed-point math in Python before touching VHDL.

## What is Q-format

`Qm.f` is a signed binary word with `m` integer bits (including the sign
bit) and `f` fractional bits, representing real numbers in steps of
`2^-f`. Q4.4, for example, is 8 bits total, step size 1/16, range
`-8` to `7.9375`.

A Q-format value is really just an integer — the same bits a register would
hold — read as `code / 2^f`. These helpers work with that integer directly,
which also makes it easy to generate bit-exact test vectors later for a
VHDL testbench.

## What's here

- `qformat.py` — four small functions: `to_int` (float → integer code, with
  rounding), `saturate` (clip a code to the representable range),
  `from_int` (integer code → float), and `quantize` (round + saturate +
  convert back, so you can ask "what do I actually get if I store this
  value as `Qm.f`?").
- `test_qformat.py` — directed tests for the edge cases: rounding ties,
  truncation, round-trip, saturation (signed and unsigned), combined
  quantize.

## Rounding

Default rounding is round-half-away-from-zero, not truncation. Truncation
is cheaper in hardware but always biases magnitude downward, and that bias
adds up across cascaded stages. `round_mode="truncate"` is there for when a
design specifically needs it.

## Running the tests

```
python3 test_qformat.py
```

## Gotchas

- `to_int` doesn't saturate by itself — call `saturate`, or just use
  `quantize` if the value might be out of range.
- Bit widths aren't validated. Garbage in, garbage out — this is a
  prototyping helper, not a hardened library.
