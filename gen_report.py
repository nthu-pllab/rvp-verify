#!/usr/bin/env python3
"""gen_report.py — render run_suite results into a report.html.

Same four-section shape as the lab's RISCOF reports (Environment / Yaml /
Summary / Results), but honestly labeled: this is a signature-capture run on
the Sail model, not a DUT-vs-Reference differential. One row per test.

Usage:  python3 gen_report.py [results_dir] [out.html]
        default: results/current next to this script -> <results_dir>/report.html
"""
import html
import subprocess
import sys
from datetime import date
from pathlib import Path

ROOT = Path(__file__).resolve().parent
RESULTS = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "results/current"
OUT = Path(sys.argv[2]) if len(sys.argv) > 2 else RESULTS / "report.html"


def run(cmd, cwd=None):
    try:
        return subprocess.run(cmd, cwd=cwd, capture_output=True, text=True).stdout.strip()
    except Exception:
        return "n/a"


rows = []
for line in (RESULTS / "results.tsv").read_text().splitlines():
    name, xlen, verdict = line.split("\t")
    rows.append((name, xlen, verdict))

n_pass = sum(1 for r in rows if r[2] == "PASS")
by_xlen = {}
for _, xlen, verdict in rows:
    t, p = by_xlen.get(xlen, (0, 0))
    by_xlen[xlen] = (t + 1, p + (verdict == "PASS"))

sail_head = run(["git", "log", "-1", "--format=%h %s"], cwd=ROOT / "sail-riscv")
sail_branch = run(["git", "branch", "--show-current"], cwd=ROOT / "sail-riscv")
suite_head = run(["git", "log", "-1", "--format=%h %s"], cwd=ROOT / "rvp-test-suite")
suite_branch = run(["git", "branch", "--show-current"], cwd=ROOT / "rvp-test-suite")
as_ver = run([str(ROOT / "riscv-binutils/build/gas/as-new"), "--version"]).splitlines()[:1]

env = [
    ("Date", str(date.today())),
    ("Model under test", f"sail-riscv `{sail_branch}` — {sail_head}"),
    ("Simulator", "build/c_emulator/sail_riscv_sim (--enable-experimental-extensions, --test-signature)"),
    ("Run configs", "build/config/rv32d_v128_e32.json / rv64d_v128_e64.json"),
    ("Assembler", f"{as_ver[0] if as_ver else 'n/a'} (ruyisdk p-dev + mulq/mulqr funct4 fix)"),
    ("Test suite", f"nthu-pllab/rvp-test-suit `{suite_branch}` — {suite_head}"),
    ("Suite origin", "riscv_ctg (lab P templates) from per-page cgf files; riscv-arch-test TEST_* macros"),
    ("Method", "assemble → link → execute on Sail; PASS = clean HTIF exit, no illegal instruction, "
               "no trap loop; memory signature captured per test (granularity 4)"),
]

spec = [
    ("P specification", "RVP draft 020 (2026-03-21), https://www.jhauser.us/RISCV/ext-P/"),
    ("ISA (rv32)", "RV32IPZicsr_Zba_Zbb_Zbkb (tests borrow non-P instructions)"),
    ("ISA (rv64)", "RV64IPZicsr_Zba_Zbb_Zbkb"),
    ("Coverage definitions", "rv32ip_cgf/pN.cgf, rv64ip_cgf/pN.cgf (per spec page)"),
]

def table(pairs):
    return "\n".join(
        f"<tr><td class='k'>{html.escape(k)}</td><td>{html.escape(v)}</td></tr>" for k, v in pairs
    )

result_rows = "\n".join(
    f"<tr class='{ 'ok' if v == 'PASS' else 'bad'}'>"
    f"<td>{i+1}</td><td>{html.escape(n)}</td><td>{x}</td><td>{html.escape(v)}</td></tr>"
    for i, (n, x, v) in enumerate(rows)
)

summary_cells = " · ".join(f"{x}: {p}/{t}" for x, (t, p) in sorted(by_xlen.items()))

OUT.write_text(f"""<!DOCTYPE html>
<html><head><meta charset="utf-8"><title>RVP 020 Sail Test Report</title>
<style>
 body {{ font: 14px/1.5 -apple-system, Helvetica, Arial, sans-serif; margin: 2rem auto; max-width: 60rem; color: #222; }}
 h1 {{ border-bottom: 2px solid #333; padding-bottom: .3rem; }}
 table {{ border-collapse: collapse; width: 100%; margin: .6rem 0 1.4rem; }}
 td, th {{ border: 1px solid #ccc; padding: .25rem .6rem; text-align: left; }}
 td.k {{ width: 14rem; font-weight: 600; background: #f6f6f6; }}
 tr.ok td:last-child {{ color: #0a7a0a; font-weight: 600; }}
 tr.bad td:last-child {{ color: #b00020; font-weight: 700; }}
 .big {{ font-size: 1.25rem; font-weight: 700; }}
</style></head><body>
<h1>RISC-V P Extension (RVP draft 020) — Sail Model Test Report</h1>

<h2>Environment</h2>
<table>{table(env)}</table>

<h2>Specification</h2>
<table>{table(spec)}</table>

<h2>Summary</h2>
<p class="big">{n_pass}/{len(rows)} PASS &nbsp; ({summary_cells})</p>

<h2>Results</h2>
<table>
<tr><th>#</th><th>test</th><th>xlen</th><th>verdict</th></tr>
{result_rows}
</table>
</body></html>
""")
print(f"{OUT}: {n_pass}/{len(rows)} PASS ({summary_cells})")
