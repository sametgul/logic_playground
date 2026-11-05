"""Test-signal generator: the single source of truth for DSP stimulus.

Every signal is quantized to signed Qm.f using the shared qformat helpers
and written as one integer code per line:

  <out_dir>/<name>.txt   signed decimal      -> read by VHDL testbenches (textio)
  <out_dir>/<name>.hex   two's-complement hex -> BRAM/ROM init for hardware

The same integer codes feed the Python golden models and the VHDL, so any
mismatch downstream is a real DUT bug, not a stimulus difference.

Use it three ways:
  - CLI:       python3 gen_signals.py        (default signal set + docs/signals.png)
  - notebook:  notebooks/generate_signals.ipynb (change parameters, build your own)
  - import:    from gen_signals import sine, add, gaussian_noise, generate
"""

import math
import os
import random
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "../../dsp01_fixed_point_basics/models"))
from qformat import saturate, to_int  # noqa: E402

# --- Defaults (match the EMA testbenches: Q2.15, Fs = 1 kHz) --------------
DEFAULT_INT_BITS = 2
DEFAULT_FRAC_BITS = 15
DEFAULT_FS = 1000.0
DEFAULT_N = 2048
DEFAULT_SEED = 1234  # fixed seed -> noisy signals are reproducible

DEFAULT_OUT_DIR = os.path.join(HERE, "../stimulus")
DEFAULT_DOC_DIR = os.path.join(HERE, "../docs")


# --- Signal building blocks (all return plain lists of floats) ------------
def sine(freq, amp, n=DEFAULT_N, fs=DEFAULT_FS, phase=0.0):
    return [amp * math.sin(2 * math.pi * freq * i / fs + phase) for i in range(n)]


def add(*signals):
    """Sample-wise sum of any number of equal-length signals."""
    return [sum(vals) for vals in zip(*signals)]


def scale(x, gain):
    return [gain * v for v in x]


def dc(level, n=DEFAULT_N):
    return [level] * n


def gaussian_noise(sigma, n=DEFAULT_N, seed=DEFAULT_SEED):
    rng = random.Random(seed)
    return [rng.gauss(0.0, sigma) for _ in range(n)]


def uniform_noise(amp, n=DEFAULT_N, seed=DEFAULT_SEED):
    """Uniform noise in [-amp, +amp]."""
    rng = random.Random(seed)
    return [rng.uniform(-amp, amp) for _ in range(n)]


def step(amp, start=10, n=DEFAULT_N):
    return [amp if i >= start else 0.0 for i in range(n)]


def impulse(amp, at=10, n=DEFAULT_N):
    return [amp if i == at else 0.0 for i in range(n)]


def square(freq, amp, n=DEFAULT_N, fs=DEFAULT_FS):
    return [amp if math.sin(2 * math.pi * freq * i / fs) >= 0 else -amp for i in range(n)]


def chirp(f0, f1, amp, n=DEFAULT_N, fs=DEFAULT_FS):
    """Linear sweep f0 -> f1 Hz over the whole record."""
    t_total = n / fs
    k = (f1 - f0) / t_total
    return [amp * math.sin(2 * math.pi * (f0 * (i / fs) + 0.5 * k * (i / fs) ** 2)) for i in range(n)]


def default_signals(fs=DEFAULT_FS, n=DEFAULT_N, seed=DEFAULT_SEED):
    """The standard set used by the EMA / cascade testbenches."""
    return {
        "sine_10hz": sine(10, 1.0, n, fs),
        # 0.8 + 0.5 = 1.3 peak, well inside Q2.15's +/-2 range
        "compound_10_100hz": add(sine(10, 0.8, n, fs), sine(100, 0.5, n, fs)),
        # 0.8 + ~4 sigma of noise (0.2*4) stays inside +/-2; saturation guards the rest
        "noisy_sine_10hz": add(sine(10, 0.8, n, fs), gaussian_noise(0.2, n, seed)),
        "step": step(1.0, n=n),
        "impulse": impulse(1.0, n=n),
        "chirp_1_200hz": chirp(1, 200, 0.9, n, fs),
    }


# --- Quantize + write -----------------------------------------------------
def to_codes(x, int_bits=DEFAULT_INT_BITS, frac_bits=DEFAULT_FRAC_BITS):
    """Floats -> saturated Qm.f integer codes."""
    return [saturate(to_int(v, frac_bits), int_bits, frac_bits) for v in x]


def count_saturated(x, codes, frac_bits=DEFAULT_FRAC_BITS):
    """How many samples were clamped by saturation (code != unclamped code)."""
    return sum(1 for v, c in zip(x, codes) if c != to_int(v, frac_bits))


def write_files(name, codes, out_dir=DEFAULT_OUT_DIR, int_bits=DEFAULT_INT_BITS, frac_bits=DEFAULT_FRAC_BITS):
    os.makedirs(out_dir, exist_ok=True)
    width = int_bits + frac_bits
    with open(os.path.join(out_dir, f"{name}.txt"), "w") as f:
        f.writelines(f"{c}\n" for c in codes)
    digits = (width + 3) // 4
    mask = (1 << width) - 1
    with open(os.path.join(out_dir, f"{name}.hex"), "w") as f:
        f.writelines(f"{c & mask:0{digits}X}\n" for c in codes)


def generate(signals, out_dir=DEFAULT_OUT_DIR, int_bits=DEFAULT_INT_BITS, frac_bits=DEFAULT_FRAC_BITS, verbose=True):
    """Quantize and write every signal in `signals` ({name: float list}); return {name: codes}."""
    all_codes = {}
    for name, x in signals.items():
        codes = to_codes(x, int_bits, frac_bits)
        write_files(name, codes, out_dir, int_bits, frac_bits)
        all_codes[name] = codes
        if verbose:
            clipped = count_saturated(x, codes, frac_bits)
            print(f"{name:20s} {len(codes)} samples, min={min(codes):7d} max={max(codes):7d}"
                  f"{f'  ({clipped} SATURATED)' if clipped else ''}")
    return all_codes


# --- Plotting -------------------------------------------------------------
def plot(all_codes, fs=DEFAULT_FS, frac_bits=DEFAULT_FRAC_BITS, int_bits=DEFAULT_INT_BITS, path=None):
    import matplotlib
    if path:
        matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    full_scale = 2 ** (int_bits - 1)
    fig, axes = plt.subplots(len(all_codes), 1, figsize=(10, 2 * len(all_codes)), sharex=True, squeeze=False)
    for ax, (name, codes) in zip(axes[:, 0], all_codes.items()):
        ax.plot([c / (1 << frac_bits) for c in codes], lw=0.8)
        ax.set_ylabel(name, rotation=0, ha="right", va="center", fontsize=8)
        ax.set_ylim(-full_scale, full_scale)
        ax.grid(alpha=0.3)
    axes[-1, 0].set_xlabel(f"sample (Fs = {fs:g} Hz)")
    fig.tight_layout()
    if path:
        fig.savefig(path, dpi=110)
        plt.close(fig)
    return fig


def main():
    all_codes = generate(default_signals())
    os.makedirs(DEFAULT_DOC_DIR, exist_ok=True)
    path = os.path.join(DEFAULT_DOC_DIR, "signals.png")
    plot(all_codes, path=path)
    print(f"plot -> {os.path.normpath(path)}")


if __name__ == "__main__":
    main()
