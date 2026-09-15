# Vendored files — where they came from

Everything outside the three submodules was copied in from the lab's
verification environment on 2026-09-15. None of it is under its original git
history any more, so this file records the base commit and what was changed on
top, to keep lab changes separable from upstream.

## `riscv-ctg/` and `env/arch-test/`

Base: **nthu-pllab/riscv-arch-test @ `3aa9b50e`** ("[ACT] Physical Memory
Protection 64 (#603)", the lab fork of riscv/riscv-arch-test). Copied from the
working tree, which carried these never-committed changes:

- `riscv-ctg/riscv_ctg/data/p.yaml` — **new file**, the P instruction templates
  (per-page covergroups; page numbers follow the draft-015 encodings PDF).
  Lab work (ChiaHuiSu).
- `riscv-ctg/riscv_ctg/dsp_function.py`, `function_generators.py`,
  `generator.py`, `constants.py`, `cross_comb.py`, `data/template.yaml`,
  `requirements.txt` — lab P support (pair-register operands, P semantics),
  plus a 2026-08-03 fix at 7 sites for Python 3.13's `locals()`/`eval`
  semantics (the generator crashed on 3.13 otherwise).
- `env/arch-test/test_macros.h` — the P `TEST_PAIR_*` macros (~150 lines on top
  of upstream). `arch_test.h`, `encoding.h`, `test_macros_vector.h` are
  upstream as of that commit.

Excluded on purpose: `riscv-isac/` (the regeneration flow installs riscv_isac
from PyPI and patches it in `setup_ctg_venv.sh`; the lab's local isac edits are
not used here), `.egg-info`, `__pycache__`.

## `coverage/dataset.cgf`

nthu-pllab/riscv-arch-test @ `3aa9b50e`, `coverage/dataset.cgf`, unmodified.
It defines the YAML anchors the suite's `rv{32,64}ip_cgf/p*.cgf` files
reference, so it must precede them on the riscv_ctg command line.

## `env/sail/`

`model_test.h` + `link.ld` from the lab RISCOF sail plugin
(`rvp/test-32/sail_cSim/env` in ChiaHuiSu's `rvp.tar.gz` environment),
unmodified.

## `results/baseline/`

Output of `run_suite.sh` + `gen_report.py` on this repo's pinned submodules;
the report's Environment table records the exact commits and date.
