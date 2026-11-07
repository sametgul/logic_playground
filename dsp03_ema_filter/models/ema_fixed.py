"""Fixed-point EMA golden model, built on the shared Q-format helper.

Input/output live at Q(int_bits).(frac_bits) - the external word width.
The accumulator is kept wider, at Q(int_bits).(frac_bits + guard_bits), and
only rounded down to the external width when read out. The guard bits
exist because alpha can be extremely small (long tau at a high sample
rate): if the accumulator had no more precision than the input/output, the
increment alpha*(x-y) rounds to zero every single step and the filter
never moves at all. See `required_guard_bits`.
"""

import math
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "../../dsp01_fixed_point_basics/models"))
from qformat import quantize


def required_guard_bits(alpha, frac_bits, target_diff=None):
    """Extra fractional bits so the filter keeps converging until diff is within target_diff.

    As y approaches x, diff = x - y shrinks every step, so alpha*diff shrinks
    too - and once it underflows below half the accumulator's LSB, the
    filter stalls at whatever diff that was, not at the true final value.
    target_diff is how small a residual diff you need to resolve before
    that's acceptable; it defaults to one output LSB (2**-frac_bits), since
    the output can't represent anything finer than that anyway.
    """
    if alpha <= 0:
        return 0
    if target_diff is None:
        target_diff = 2 ** -frac_bits
    needed_total_frac_bits = math.ceil(-math.log2(alpha * target_diff))
    return max(0, needed_total_frac_bits - frac_bits)


def ema_filter_fixed(x, alpha, int_bits, frac_bits, guard_bits=0, round_mode="half_up"):
    """Run the fixed-point EMA recursion over x, returning output at the native Q(int_bits).(frac_bits) width.

    round_mode defaults to "half_up" (ties toward +infinity) because that is
    what ema_filter.vhd does: round_shift() adds half an LSB and then does an
    arithmetic shift, which is a floor. "nearest" (ties away from zero) needs
    extra sign-dependent logic in hardware and would disagree with the VHDL
    on every negative exact tie.

    Float-based, so it is only bit-exact against the VHDL while every
    intermediate fits in a float64 mantissa (53 bits). For the bit-exact
    reference at any width use ema_filter_codes() below.
    """
    acc_frac_bits = frac_bits + guard_bits
    alpha_q = quantize(alpha, int_bits=0, frac_bits=acc_frac_bits, signed=False, round_mode=round_mode)

    y = 0.0  # accumulator, kept quantized at acc_frac_bits
    y_out = [0.0] * len(x)
    for n in range(len(x)):
        x_q = quantize(x[n], int_bits, frac_bits, round_mode=round_mode)
        diff = x_q - y
        increment = quantize(alpha_q * diff, int_bits, acc_frac_bits, round_mode=round_mode)
        y = quantize(y + increment, int_bits, acc_frac_bits, round_mode=round_mode)
        y_out[n] = quantize(y, int_bits, frac_bits, round_mode=round_mode)
    return y_out


# ---------------------------------------------------------------------------
# Integer (code-level) reference model - the bit-exact twin of ema_filter.vhd.
#
# Everything below is plain Python int arithmetic, so there is no float
# mantissa limit: at the VHDL's default Q3.21 + 20 guard bits the product
# diff*alpha is ~84 bits wide, far past float64's 53. Python's ">>" on a
# negative int is an arithmetic shift (floor), exactly like VHDL's
# shift_right on signed, so round_shift() below is the same operation as the
# VHDL function of the same name.
# ---------------------------------------------------------------------------


def _round_shift(v, shift):
    """Round-half-up right shift: add half the dropped weight, then floor-shift. Mirrors VHDL round_shift()."""
    if shift == 0:
        return v
    return (v + (1 << (shift - 1))) >> shift


def _saturate(v, width):
    """Clamp v to the signed range of `width` bits. Mirrors VHDL saturate_resize()."""
    return max(-(1 << (width - 1)), min((1 << (width - 1)) - 1, v))


def alpha_to_code(alpha, frac_bits, guard_bits=0):
    """Quantize alpha to the unsigned Q0.(frac_bits+guard_bits) integer fed to the VHDL alpha_i port."""
    acc_frac_bits = frac_bits + guard_bits
    code = math.floor(alpha * (1 << acc_frac_bits) + 0.5)
    return max(0, min((1 << acc_frac_bits) - 1, code))


def ema_filter_codes(x_codes, alpha_code, int_bits, frac_bits, guard_bits=0, stats=None):
    """Bit-exact EMA over integer sample codes; returns integer output codes (same Q format as the input).

    Mirrors ema_filter.vhd step for step:
      x_aligned = x << guard;  diff = x_aligned - y
      increment = round_shift(diff * alpha_code, acc_frac_bits)
      y         = saturate(y + increment)
      out       = saturate(round_shift(y, guard))

    If `stats` is a dict, stats["diff_overflows"] is set to the number of
    samples where diff did not fit the accumulator width. The VHDL computes
    diff in ACC_WIDTH bits with plain "-", so on those samples it wraps while
    this model (ideal arithmetic) does not - a nonzero count means the two
    are expected to disagree, and it is the VHDL that is wrong.
    """
    data_width = int_bits + frac_bits
    acc_frac_bits = frac_bits + guard_bits
    acc_width = int_bits + acc_frac_bits
    lo, hi = -(1 << (data_width - 1)), (1 << (data_width - 1)) - 1

    y = 0
    out = []
    diff_overflows = 0
    for xc in x_codes:
        if not lo <= xc <= hi:
            raise ValueError(f"input code {xc} does not fit {data_width} signed bits")
        diff = (xc << guard_bits) - y
        if diff != _saturate(diff, acc_width):
            diff_overflows += 1
        increment = _round_shift(diff * alpha_code, acc_frac_bits)
        y = _saturate(y + increment, acc_width)
        out.append(_saturate(_round_shift(y, guard_bits), data_width))
    if stats is not None:
        stats["diff_overflows"] = diff_overflows
    return out
