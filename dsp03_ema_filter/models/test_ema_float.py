"""Directed tests for ema_float.py. Run with: python3 test_ema_float.py"""

import numpy as np
from scipy import signal

from ema_float import alpha_from_tau, ema_filter, f3db


def test_alpha_from_tau_bounds():
    Ts = 1e-6
    assert 0 < alpha_from_tau(tau=1e-3, Ts=Ts) < 1
    # tau >> Ts -> alpha close to 0 (slow filter)
    assert alpha_from_tau(tau=1.0, Ts=Ts) < 1e-5
    # tau close to Ts -> alpha close to 1 (fast filter)
    assert alpha_from_tau(tau=Ts, Ts=Ts) > 0.6


def test_step_response_matches_analytic():
    Ts = 1e-6
    tau = 1e-3
    alpha = alpha_from_tau(tau, Ts)

    n_samples = int(10 * tau / Ts)
    t = np.arange(n_samples) * Ts
    x = np.ones(n_samples)
    y = ema_filter(x, alpha)

    analytic = 1 - np.exp(-t / tau)
    assert np.max(np.abs(y - analytic)) < 1e-3


def test_f3db_matches_freqz():
    Ts = 1e-6
    tau = 1e-3
    alpha = alpha_from_tau(tau, Ts)

    # discrete transfer function: y[n] = (1-alpha) y[n-1] + alpha x[n]
    b, a = [alpha], [1, -(1 - alpha)]
    f3db_theory = f3db(tau, n=1)

    w, h = signal.freqz(b, a, worN=[f3db_theory], fs=1 / Ts)
    mag_db = 20 * np.log10(np.abs(h[0]))
    assert abs(mag_db - (-3.0)) < 0.05


def test_f3db_scales_with_order():
    tau = 1e-3
    # higher-order cascade has a lower -3dB bandwidth for the same tau
    assert f3db(tau, n=4) < f3db(tau, n=1)


if __name__ == "__main__":
    tests = [v for k, v in list(globals().items()) if k.startswith("test_")]
    for t in tests:
        t()
        print(f"PASS {t.__name__}")
    print(f"{len(tests)} tests passed")
