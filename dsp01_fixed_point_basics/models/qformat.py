"""Shared Q-format fixed-point helpers.

Q format here means signed Qm.f: m integer bits (including the sign bit),
f fractional bits. A Qm.f value is really just an ordinary integer `code`;
the real number it represents is `code / 2**f`. `2**f` is the scale factor
- think "cents per dollar" for fractional bits: a register has no decimal
point of its own, so storing 0.3 at f=4 (step size 1/16) means rounding
0.3 to the nearest multiple of 1/16 and keeping that as a plain integer
count of sixteenths (0.3 * 16 = 4.8 -> rounds to the integer 5).
"""

import math


def to_int(x, frac_bits, round_mode="nearest"):
    """Convert a float to its Q-format integer code (no saturation)."""
    scaled = x * (1 << frac_bits)  # x measured in ticks of size 2**-frac_bits
    if round_mode == "truncate":
        # Floor, not round-toward-zero: dropping the least-significant bits
        # of a two's-complement number always rounds toward -infinity, which
        # is where the one-sided bias actually comes from.
        return math.floor(scaled)
    if round_mode == "nearest":
        return int(scaled + 0.5) if scaled >= 0 else -int(-scaled + 0.5)
    raise ValueError(f"unknown round_mode: {round_mode}")


def from_int(code, frac_bits):
    """Convert a Q-format integer code back to float."""
    return code / (1 << frac_bits)


def saturate(code, int_bits, frac_bits, signed=True):
    """Clamp an integer code to the representable range of Qm.f."""
    total_bits = int_bits + frac_bits
    if signed:
        lo, hi = -(1 << (total_bits - 1)), (1 << (total_bits - 1)) - 1
    else:
        lo, hi = 0, (1 << total_bits) - 1
    return max(lo, min(hi, code))


def quantize(x, int_bits, frac_bits, signed=True, round_mode="nearest"):
    """Round and saturate a float to its Qm.f representation, returned as float."""
    code = saturate(to_int(x, frac_bits, round_mode), int_bits, frac_bits, signed)
    return from_int(code, frac_bits)
