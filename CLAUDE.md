# CLAUDE.md

Context for the lock-in amplifier filter initiative in this repo. General VHDL conventions live in `gu00_vhdl_template/`, `gu01_vhdl_tricks/`, and `gu03_uvvm_verification_guide/` — read those for coding/testbench style. This file only covers decisions specific to the lock-in project that aren't visible anywhere else in the repo.

## Goal

Replicate the demodulator filter chain used in the Stanford SR860 and Zurich Instruments MFLI lock-in amplifiers, as a from-scratch VHDL implementation. Portfolio piece, also usable for SERF/ASG work.

## Architecture decisions (already made, don't relitigate)

- **Bus standard**: AXI4-Stream for the sample path (ADC → filter → decimator → demod — unidirectional, valid/ready, no addresses). AXI4-Lite for runtime config (coefficients, gain, enable, status — register access, no bursts). Full AXI4 is not used anywhere in this chain; it would only apply to something like DMA to DDR, which is out of scope.
- **Filter math**: cascade of first-order IIR (EMA) stages, `y += α(x − y)`, `α = 1 − exp(−Ts/τ)`. SR860 gives n=1..4 (6/12/18/24 dB/oct); MFLI goes to n=8 (48 dB/oct). A sync/sinc filter stage (integer number of reference periods) kills the 2f ripple at low frequencies — separate from the EMA cascade.
- **Known hardware problem to design around**: long τ at high sample rates makes α tiny (e.g. τ=1s @ 1MSa/s → α≈1e-6), which needs extra accumulator bits per stage and causes quantization buildup across the cascade. Real instruments solve this with multirate processing — decimate after the mixer (CIC + compensation) and run the IIR stages at the lower rate. This is *why* CIC decimation is in the roadmap before the sinc filter, not an optional add-on.

## Roadmap (build in this order)

0. `dsp01_fixed_point_basics` — shared Q-format quantize/round/saturate helper (`models/qformat.py`; later blocks' `models/` import it via relative path). Not a VHDL block itself, just the infra every later fixed-point model reuses. **Status: done.**
1. `dsp02_ema_filter` — single EMA stage, fixed-point. **Not started yet** — don't jump ahead to this.
2. `dsp03_ema_cascade` — n-stage cascade, runtime-configurable τ/order
3. NCO + mixer (may reuse/extend `ip00_sine_dds_block`'s DDS compiler work rather than a fresh `dsp0X`)
4. `dsp0X_cic_decimator` — CIC decimation ahead of the LPF, plus CIC compensation FIR for passband droop
5. `dsp0X_sinc_filter`
6. Full lock-in core, AXI4-Stream throughout — integrates 1-5 plus the AXI4-Lite config wrapper and X/Y/R/θ (CORDIC) (closer in shape to `z01_custom_AXI4_per` than to a plain `dsp0X` module). Large enough it likely gets its own top-level folder once the sub-blocks exist.

Side modules, not on the lock-in critical path, picked up opportunistically: DC blocker, biquad/notch (50 Hz rejection), half-band FIR. Later/optional, only once a problem actually needs them: LMS adaptive filter, Kalman filter.

Follow the existing `dsp0X_name/{README.md,docs/,src/}` convention per block (see `dsp00_lfsr/` as the template) — Python golden-model files live in a `models/` subfolder and notebooks in `notebooks/` alongside `docs/` and `src/`; testbenches stay inside `src/` next to the VHDL (e.g. `tb_lfsr.vhd` beside `lfsr.vhd`), not a separate `tb/` tree. Don't restructure already-built blocks to match; this applies going forward.

## Per-block verification loop

Each block goes through five steps, in order, to isolate which layer broke when something's wrong:

1. **Float model** (Python, in `models/`) — is the algorithm right? Check frequency response, step response, noise bandwidth against theory.
2. **Fixed-point model** (Python, same `models/` folder, e.g. `ema_fixed.py` alongside `ema_float.py`) — same algorithm, exact bit widths/rounding/saturation the VHDL will use, built on `dsp01_fixed_point_basics/models/qformat.py`. Compare against the float model; this is where bit widths get chosen, before any VHDL.
3. **VHDL implementation** — direct translation of the fixed-point model. No design decisions left at this point.
4. **Bit-exact simulation** — the fixed-point model generates input/expected-output vectors; the GHDL/NVC + UVVM testbench (on the Mac) must match exactly, including random AXI4-Stream stalls. Any mismatch here is a VHDL bug, since the algorithm was already proven in steps 1-2.
5. **Hardware test** (Windows machine at the lab) — synthesize, check timing/resources, run on the board. Compare against the MFLI/SR860 with the same input signal where possible.

Write a one-page `docs/<block>.md` per block: what it is, its response, its cost, when to use it, when not to. After the side modules (phase 6) these notes become the actual filter-selection repertoire — the point isn't just the lock-in chain, it's building judgment for future filter choices generally.

## Golden-model workflow

Prototype the float model first in a Jupyter notebook (VS Code, `.venv` with numpy/scipy/matplotlib/ipykernel) under `<block>/notebooks/`, validate against real MFLI hardware output where possible (same TC/order — compare step response and noise), then promote the settled model into `<block>/models/<name>_float.py`. Build the fixed-point model (`<name>_fixed.py`) from there per the verification loop above. VHDL testbench vector generation imports from the fixed-point module, so notebook and testbench never drift out of bit-exact sync. Theory references: SR860/MFLI demodulator manual chapters, Zurich's "Principles of lock-in detection" white paper — n-th order 3dB bandwidth is `f₃dB = √(2^(1/n) − 1) / (2πτ)`.

## Platform split (this machine is a Mac)

Works here: Python, notebooks, VHDL authoring, GHDL/NVC simulation (`brew install ghdl`; check Apple Silicon support, NVC is a solid alternative).
Does not work here: Vivado (no macOS build; Apple Silicon VM is painful, needs x86) and LabVIEW FPGA (Windows-only). Synthesis, timing closure, and hardware tests happen on the Windows machine at the lab; git is the sync point between the two sides.

## Open question

ADC sample rate and the range of τ actually used in experiments — not yet answered. This determines accumulator bit-widths per EMA stage and whether/where multirate decimation becomes mandatory rather than just good practice. Ask before finalizing bit-widths in `dsp02_ema_filter`/`dsp03_ema_cascade`.
