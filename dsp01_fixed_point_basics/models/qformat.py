"""Shared Q-format fixed-point helpers.

Q format here means signed Qm.f: m integer bits (including the sign bit),
f fractional bits, scale = 2**f. Reused by every block's fixed-point model
(CLAUDE.md roadmap phase 0).
"""


def to_int(x, frac_bits, round_mode="nearest"):
    """Convert a float to its Q-format integer code (no saturation)."""
    scaled = x * (1 << frac_bits)
    if round_mode == "truncate":
        return int(scaled) if scaled >= 0 else -int(-scaled)
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
