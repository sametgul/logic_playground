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


def ema_filter_fixed(x, alpha, int_bits, frac_bits, guard_bits=0, round_mode="nearest"):
    """Run the fixed-point EMA recursion over x, returning output at the native Q(int_bits).(frac_bits) width."""
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
