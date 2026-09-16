# rvp-verify — RISC-V P extension (RVP draft 020) verification for sail-riscv

A self-contained environment to build the [sail-riscv](https://github.com/riscv/sail-riscv)
model with the proposed P (packed-SIMD / DSP) extension, run a suite of
764 generated P tests on it and produce a report. It is the verification
evidence behind the P-extension pull request to riscv/sail-riscv.

Specification: RVP draft 020 (2026-03-21) by John Hauser,
https://www.jhauser.us/RISCV/ext-P/ (`RVP-baseInstrs-020.pdf`,
`RVP-instrEncodings-020.pdf`, `RVP-baseInstrs-Sail-020.txt`).

```
git clone --recursive <this repo>
cd rvp-verify
./build.sh            # P-aware binutils + sail-riscv simulator
./run_suite.sh        # 764 tests -> results/current/
python3 gen_report.py # results/current/report.html
```

A `README.zh-TW.md` with the same content in Chinese is kept for the lab.

## Contents

| Path | What it is |
|---|---|
| `sail-riscv/` | submodule: the model under test (nthu-pllab fork of riscv/sail-riscv, branch `pext-020-rebase`) |
| `rvp-test-suite/` | submodule: 764 riscv_ctg-generated `.S` tests (446 RV32, 318 RV64) plus the cgf coverpoint files they were generated from |
| `riscv-binutils/` | submodule: P-aware binutils (ruyisdk `p-dev` branch plus a `mulq`/`mulqr` encoding fix) |
| `env/arch-test/` | riscv-arch-test `arch_test.h`, `encoding.h` and `test_macros.h` extended with the register-pair `TEST_PAIR_*` macros |
| `env/sail/` | `model_test.h` and `link.ld` for the Sail target |
| `riscv-ctg/` | the test generator with P support (templates in `riscv_ctg/data/p.yaml`, semantics in `dsp_function.py`) |
| `coverage/dataset.cgf` | shared YAML anchors referenced by the suite's cgf files |
| `results/baseline/` | reference run: `report.html`, `results.tsv` and one memory signature per test |
| `build.sh`, `run_suite.sh`, `gen_report.py`, `verify_insn.sh`, `regen_tests.sh`, `setup_ctg_venv.sh` | scripts, described below |
| `VENDOR.md` | provenance of the vendored files and what was changed in them |

## Building

Requirements: a C/C++ toolchain, CMake, Python 3, opam with Sail 0.20.2
(`opam install sail.0.20.2 && eval $(opam env)`), and a
`riscv64-unknown-elf-gcc` for preprocessing only (any recent version; on
`PATH`, or set `RISCV=<prefix>` or `RISCV_GCC=<path>`).

```
./build.sh            # incremental; builds binutils only if missing
./build.sh --fresh    # reconfigure and rebuild both from scratch
```

`build.sh` produces `riscv-binutils/build/gas/as-new`,
`riscv-binutils/build/ld/ld-new` and
`sail-riscv/build/c_emulator/sail_riscv_sim`. Upstream sail-riscv fetches
asio from sourceforge at configure time; if that download fails, unpack
[asio 1.36.0](https://github.com/chriskohlhoff/asio/archive/refs/tags/asio-1-36-0.tar.gz)
somewhere and run `ASIO_SRC=<dir>/asio ./build.sh`.

## Running the suite

```
LIMIT=2 ./run_suite.sh   # smoke test: two tests per suite
./run_suite.sh           # full run -> results/current/
python3 gen_report.py    # -> results/current/report.html
```

For every test: `gcc -E` (with `-march=rv32i`/`rv64i` so that the
`TEST_PAIR_*` macros see `__riscv_xlen`), the P-aware `as`
(`-march=rv{32,64}ip_zicsr_zba_zbb_zbkb`, the tests borrow a few non-P
instructions), `ld`, then `sail_riscv_sim --enable-experimental-extensions
--test-signature`. Verdicts are `PASS`, `PP_FAIL`, `AS_FAIL`, `LD_FAIL`,
`TIMEOUT`, `INST_LIMIT` (no HTIF exit within the instruction budget) or
`RUN_FAIL(rc=N)`. Tool locations can be overridden
with `AS`, `LD`, `SAILDIR`, `SAIL`, `RISCV_GCC` and `OUT`.

Expected result: 764/764 PASS. The per-test signatures land in
`results/current/sig_rv{32,64}_<group>_<test>.sig` (the same test name can
occur in several instruction groups, hence the group in the file name) and
can be compared with the reference run:

```
diff -rq results/baseline results/current --exclude=report.html --exclude=tmp
```

## What the result means

Only the Sail side is exercised here; there is no second implementation to
compare against, since no P-enabled Spike or other reference for draft 020
is publicly available yet. PASS means the test assembled, linked and ran to
the HTIF exit (the simulator's SUCCESS line) with no illegal instruction. The
signatures are produced by the model itself, so diffing them shows changes
between model versions, not disagreement with the specification.

Semantics were checked separately against Hauser's `RVP-baseInstrs-Sail-020.txt`
(Sail-style pseudo-code for the instructions that changed relative to the
old P proposal), and encodings were round-tripped through binutils
(`verify_insn.sh`, below). The report's Coverage section lists, per XLEN,
how many of the model's P mnemonics have at least one test and which do not.

## Checking a single instruction

```
./verify_insn.sh aadd "6,4=>5" "-0x80000000,0x7fffffff=>0xffffffff"
XLEN=64 ./verify_insn.sh <mnemonic> "rs1,rs2=>expected"
```

Assembles `<mnemonic> a5,a3,a4` with binutils, checks that the model decodes
the same bytes back to the same mnemonic (catches wrong bits and clause
collisions), then runs each `rs1,rs2=>expected` case and compares `rd`. You
supply `expected` from the specification. Only the three-register form is
supported.

## Regenerating tests (advanced)

```
./setup_ctg_venv.sh          # create ctg-venv/ (idempotent; --fresh to rebuild)
./regen_tests.sh rv32 p20    # regenerate one cgf group into ./regen_out/
```

riscv_ctg is a constraint solver plus template engine: the cgf coverpoints
say what to cover and `p.yaml` says which values may be drawn; it does not
know legal operand ranges itself, so the assembler is the only range check.
Regenerated `.S` files are reviewed by hand before being copied into
`rvp-test-suite/`; nothing is adopted automatically. The cgf/`p.yaml` groups
are named after the pages of an older encodings draft (015); use instruction
names, not group numbers, when communicating outside this repository.

## Known toolchain issues

The P-aware binutils used here is the ruyisdk `p-dev` branch. Two encoding
bugs were found while cross-checking against draft 020 and have been
reported: `mulq`/`mulqr` used funct4 1011 instead of 1010 (fixed in the
submodule's branch), and RV32 `psshl.dhs`/`psshl.dws` are emitted with
funct3 100 instead of 010 (the model follows the spec, so these two cannot
be round-tripped). The 020-only mnemonics `pnclipp.*`/`pnclipup.*` are not
known to this binutils yet.

## License

BSD-3-Clause for the scripts and files written for this repository; see
`LICENSE` for the licenses of the vendored riscv-ctg and riscv-arch-test
material. The submodules are separate projects under their own licenses.
