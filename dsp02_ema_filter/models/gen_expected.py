"""Generate the expected (golden) output file for the bit-exact VHDL comparison.

Reads a stimulus file from dsp03_test_signals (one signed integer code per
line), runs it through the integer EMA model, and writes the expected output
codes in the same one-integer-per-line format the VHDL testbench writes.

Example (the standard setup: Q2.15, Ts = 1 ms, tau = 10 ms -> alpha code 3118):

    python3 gen_expected.py ../../dsp03_test_signals/stimulus/sine_10hz.txt \
        -o ../sim/sine_10hz_expected.txt --tau 10e-3 --ts 1e-3

The alpha code is printed so you can paste the same number into the testbench.
"""

import argparse
import os
import sys

from ema_fixed import alpha_to_code, ema_filter_codes
from ema_float import alpha_from_tau


def read_codes(path):
    with open(path) as f:
        return [int(line) for line in f if line.strip()]


def write_codes(path, codes):
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    with open(path, "w") as f:
        for c in codes:
            f.write(f"{c}\n")


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("stimulus", help="input .txt, one signed integer code per line")
    p.add_argument("-o", "--output", required=True, help="expected output .txt to write")
    p.add_argument("--int-bits", type=int, default=2)
    p.add_argument("--frac-bits", type=int, default=15)
    p.add_argument("--guard-bits", type=int, default=0)
    g = p.add_mutually_exclusive_group(required=True)
    g.add_argument("--alpha-code", type=int, help="alpha_i port value (unsigned Q0.(frac+guard) integer)")
    g.add_argument("--tau", type=float, help="time constant in seconds (needs --ts)")
    p.add_argument("--ts", type=float, help="sample period in seconds (with --tau)")
    args = p.parse_args()

    if args.tau is not None:
        if args.ts is None:
            p.error("--tau needs --ts")
        alpha = alpha_from_tau(args.tau, args.ts)
        alpha_code = alpha_to_code(alpha, args.frac_bits, args.guard_bits)
    else:
        alpha_code = args.alpha_code

    x = read_codes(args.stimulus)
    stats = {}
    y = ema_filter_codes(x, alpha_code, args.int_bits, args.frac_bits, args.guard_bits, stats=stats)
    write_codes(args.output, y)

    print(f"alpha_code = {alpha_code}  ({len(x)} samples -> {args.output})")
    if stats["diff_overflows"]:
        print(
            f"WARNING: diff overflowed the accumulator on {stats['diff_overflows']} samples; "
            "the VHDL wraps there and will not match this model",
            file=sys.stderr,
        )


if __name__ == "__main__":
    main()
