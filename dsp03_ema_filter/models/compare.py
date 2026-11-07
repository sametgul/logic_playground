"""Compare the VHDL testbench output against the golden expected file.

    python3 compare.py ../sim/sine_10hz_expected.txt ../sim/sine_10hz_actual.txt

Both files hold one signed integer code per line. Exit status 0 only if the
files have the same length and every sample is identical (bit-exact).
"""

import sys

from gen_expected import read_codes

MAX_SHOWN = 10


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    expected, actual = read_codes(sys.argv[1]), read_codes(sys.argv[2])

    bad = [i for i, (e, a) in enumerate(zip(expected, actual)) if e != a]
    ok = not bad and len(expected) == len(actual)

    if len(expected) != len(actual):
        print(f"LENGTH MISMATCH: expected {len(expected)} samples, actual {len(actual)}")
    if bad:
        print(f"{len(bad)} of {min(len(expected), len(actual))} samples differ; first {min(MAX_SHOWN, len(bad))}:")
        print(f"{'idx':>6} {'expected':>10} {'actual':>10} {'diff':>6}")
        for i in bad[:MAX_SHOWN]:
            print(f"{i:>6} {expected[i]:>10} {actual[i]:>10} {actual[i] - expected[i]:>6}")
        worst = max(abs(actual[i] - expected[i]) for i in bad)
        print(f"max |diff| = {worst} LSB")
    if ok:
        print(f"PASS: {len(expected)} samples bit-exact")
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
