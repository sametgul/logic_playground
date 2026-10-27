"""Directed boundary tests for qformat.py. Run with: python3 test_qformat.py"""

from qformat import to_int, from_int, saturate, quantize


def test_round_nearest_ties():
    assert to_int(0.5, frac_bits=0) == 1       # ties away from zero
    assert to_int(-0.5, frac_bits=0) == -1
    assert to_int(1.5, frac_bits=0) == 2
    assert to_int(0.25, frac_bits=1) == 1       # 0.25 * 2 = 0.5 -> 1


def test_truncate():
    assert to_int(1.9, frac_bits=0, round_mode="truncate") == 1
    assert to_int(-1.9, frac_bits=0, round_mode="truncate") == -1


def test_round_trip():
    code = to_int(3.25, frac_bits=4)
    assert from_int(code, frac_bits=4) == 3.25


def test_saturate_signed():
    # Q4.0 signed: 4 bits total, range [-8, 7]
    assert saturate(7, int_bits=4, frac_bits=0) == 7
    assert saturate(8, int_bits=4, frac_bits=0) == 7
    assert saturate(-8, int_bits=4, frac_bits=0) == -8
    assert saturate(-9, int_bits=4, frac_bits=0) == -8


def test_saturate_unsigned():
    # U4.0 unsigned: range [0, 15]
    assert saturate(15, int_bits=4, frac_bits=0, signed=False) == 15
    assert saturate(16, int_bits=4, frac_bits=0, signed=False) == 15
    assert saturate(-1, int_bits=4, frac_bits=0, signed=False) == 0


def test_quantize_clips_and_rounds():
    # Q4.4 signed: 8 bits total, range [-8, 7.9375], step 1/16
    assert quantize(100.0, int_bits=4, frac_bits=4) == 7.9375
    assert quantize(-100.0, int_bits=4, frac_bits=4) == -8.0
    assert quantize(1.0 / 16, int_bits=4, frac_bits=4) == 1.0 / 16


if __name__ == "__main__":
    tests = [v for k, v in list(globals().items()) if k.startswith("test_")]
    for t in tests:
        t()
        print(f"PASS {t.__name__}")
    print(f"{len(tests)} tests passed")
