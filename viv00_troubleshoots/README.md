# Vivado Troubleshooting Log

Quick-reference for issues encountered during Vivado development.

---

## Index

| # | Issue | Status |
|---|-------|--------|
| [001](#issue-001) | Clock Wizard not generating VHDL instantiation template | Resolved |

---

## Issue 001 — Clock Wizard not generating VHDL instantiation template

**Symptom:** `.vho` file not visible in Vivado's Sources panel after generating Clock Wizard IP.

**Root cause:** Vivado generates the `.vho` file on disk but does not always display it in the GUI.

**Fix:**
1. Check the IP output directory directly — the `.vho` file is there even if not shown in Vivado.
2. Alternatively: change the project target language to Verilog, then switch back to VHDL to force regeneration.

**Reference:** [AMD Support Thread](https://adaptivesupport.amd.com/s/question/0D52E00006iI5CaSAK/vivado-not-generating-vhdl-instantiation-templates-for-clock-wizard?language=en_US)

![Vivado Clock Wizard fix screenshot](docs/clock_wiz.png)
