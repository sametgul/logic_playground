"""Directed tests for ema_fixed.py. Run with: python3 test_ema_fixed.py"""

import numpy as np

from ema_fixed import ema_filter_fixed, required_guard_bits
from ema_float import alpha_from_tau, ema_filter


def test_tracks_float_model_in_normal_case():
    # tau only a handful of Ts: alpha isn't tiny, no guard bits needed
    Ts = 1e-3
    tau = 1e-2
    alpha = alpha_from_tau(tau, Ts)

    n_samples = 200
    x = np.ones(n_samples)
    y_float = ema_filter(x, alpha)
    y_fixed = ema_filter_fixed(x, alpha, int_bits=2, frac_bits=15, guard_bits=0)

    assert np.max(np.abs(np.array(y_fixed) - y_float)) < 1e-3


def test_tiny_alpha_stalls_without_guard_bits():
    # CLAUDE.md's exact example: tau=1s @ 1MSa/s -> alpha ~ 1e-6
    Ts = 1e-6
    tau = 1.0
    alpha = alpha_from_tau(tau, Ts)
    assert alpha < 2e-6  # sanity check this really is the tiny-alpha regime

    x = np.ones(1000)
    y_fixed = ema_filter_fixed(x, alpha, int_bits=1, frac_bits=15, guard_bits=0)

    # every sample rounds to zero increment -> output never leaves its initial value
    assert all(v == y_fixed[0] for v in y_fixed)
    assert y_fixed[0] == 0.0


def test_guard_bits_fix_the_stall():
    # Same tiny alpha as above, but run long enough to actually approach
    # steady state (not just take a few steps), since the bug is that the
    # filter can stall partway through convergence, not just at the start.
    Ts = 1e-6
    tau = 1.0
    alpha = alpha_from_tau(tau, Ts)
    frac_bits = 15

    guard_bits = required_guard_bits(alpha, frac_bits)
    assert guard_bits > 0

    n_samples = int(3 * tau / Ts)
    x = np.ones(n_samples)
    y_float = ema_filter(x, alpha)
    y_fixed = ema_filter_fixed(x, alpha, int_bits=1, frac_bits=frac_bits, guard_bits=guard_bits)

    # converges close to the float model's final value, not just "moved"
    assert abs(y_fixed[-1] - y_float[-1]) < 2 * 2 ** -frac_bits


def test_saturates_on_overflow():
    alpha = 0.5
    x = [100.0] * 10  # way outside Q2.4's signed range of [-2, 1.9375]
    y_fixed = ema_filter_fixed(x, alpha, int_bits=2, frac_bits=4, guard_bits=0)
    assert y_fixed[-1] == 1.9375  # clipped to the positive rail, not wrapped


if __name__ == "__main__":
    tests = [v for k, v in list(globals().items()) if k.startswith("test_")]
    for t in tests:
        t()
        print(f"PASS {t.__name__}")
    print(f"{len(tests)} tests passed")
