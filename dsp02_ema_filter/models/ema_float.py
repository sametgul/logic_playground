"""Floating-point EMA (first-order IIR) golden model.

y[n] = y[n-1] + alpha * (x[n] - y[n-1]), alpha = 1 - exp(-Ts/tau).
"""

import numpy as np


def alpha_from_tau(tau, Ts):
    """Convert a time constant tau to the EMA coefficient alpha for sample period Ts."""
    return 1 - np.exp(-Ts / tau)


def ema_filter(x, alpha, y0=0.0):
    """Run the EMA filter over sequence x, starting from initial state y0."""
    y = np.empty_like(x, dtype=float)
    y_prev = y0
    for n in range(len(x)):
        y_prev = y_prev + alpha * (x[n] - y_prev)
        y[n] = y_prev
    return y


def f3db(tau, n=1):
    """n-th order cascade -3dB bandwidth (Hz) for n identical stages, each with time constant tau."""
    return np.sqrt(2 ** (1 / n) - 1) / (2 * np.pi * tau)
