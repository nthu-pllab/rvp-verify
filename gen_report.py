#!/usr/bin/env python3
"""gen_report.py — render run_suite.sh results into a self-contained report.html.

Sections: Environment / Specification / Summary / Coverage / Results, one
row per test. The signatures come from the Sail model itself; there is no
second implementation in the loop.

Usage:  python3 gen_report.py [results_dir] [out.html]
        default: results/current next to this script -> <results_dir>/report.html
"""
import html
import re
import subprocess
import sys
from datetime import date
from pathlib import Path

ROOT = Path(__file__).resolve().parent
RESULTS = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "results/current"
OUT = Path(sys.argv[2]) if len(sys.argv) > 2 else RESULTS / "report.html"
MODEL = ROOT / "sail-riscv/model/extensions/P"


def run(cmd, cwd=None):
    try:
        return subprocess.run(cmd, cwd=cwd, capture_output=True, text=True).stdout.strip()
    except Exception:
        return "n/a"


# ---------------------------------------------------------------- results
rows = []
for line in (RESULTS / "results.tsv").read_text().splitlines():
    name, xlen, verdict = line.split("\t")
    rows.append((name, xlen, verdict))

n_pass = sum(1 for r in rows if r[2] == "PASS")
by_xlen = {}
for _, xlen, verdict in rows:
    t, p = by_xlen.get(xlen, (0, 0))
    by_xlen[xlen] = (t + 1, p + (verdict == "PASS"))

# ---------------------------------------------------------------- coverage
# Mnemonics the suite exercises: test names are <page>/<mnemonic>-<n>.
tested = {"rv32": set(), "rv64": set()}
for name, xlen, _ in rows:
    mnem = re.sub(r"-\d+$", "", name.split("/", 1)[1])
    tested[xlen].add(mnem)

# Mnemonics the model implements. Each XLEN gets the assembly clauses of its own
# files (pext_common plus pext_32_only or pext_64_only); a clause either spells
# the mnemonic out or refers to a `..._mnemonic...` mapping, which may live in
# another file (the RV64 sati/usati/srari reuse the RV32 mapping, for example).
NOT_MNEMONIC = re.compile(r"^(x|f|v|zero|ra|sp|gp|tp|t[0-9]|s[0-9]+|a[0-9]|rd|rs1|rs2)$")
BORROWED = {"clz", "clzw", "max", "maxu", "min", "minu", "pack", "rev8", "sext.b", "sext.h", "sh1add"}
STRING = re.compile(r'"([a-z][a-z0-9]*(?:\.[a-z0-9]+)*)"')


def mnemonic_tables():
    tables = {}
    for f in MODEL.glob("*.sail"):
        for m in re.finditer(r"mapping\s+(\w+)\s*:[^{]*<->\s*string\s*=\s*\{(.*?)\}", f.read_text(), re.S):
            tables[m.group(1)] = {x for x in STRING.findall(m.group(2)) if not NOT_MNEMONIC.match(x)}
    return tables


def model_mnemonics(files, tables):
    found = set()
    for f in files:
        p = MODEL / f
        if not p.exists():
            return None
        for m in re.finditer(r"mapping clause assembly\s*=(.*?)\n\s*when\b", p.read_text(), re.S):
            clause = m.group(1)
            found |= {x for x in STRING.findall(clause) if not NOT_MNEMONIC.match(x)}
            for name in re.findall(r"\b(\w+_mnemonic\w*)\s*\(", clause):
                found |= tables.get(name, set())
    return found


tables = mnemonic_tables()
implemented = {
    "rv32": model_mnemonics(["pext_common.sail", "pext_32_only.sail"], tables),
    "rv64": model_mnemonics(["pext_common.sail", "pext_64_only.sail"], tables),
}

coverage_rows = []
untested_lists = []
for xlen in ("rv32", "rv64"):
    impl = implemented[xlen]
    tst = tested[xlen] - BORROWED
    if impl is None:
        coverage_rows.append((xlen, len(tst), "n/a", "n/a"))
        continue
    untested = sorted(impl - tst)
    coverage_rows.append((xlen, len(tst & impl), len(impl), len(untested)))
    untested_lists.append((xlen, untested))

# ---------------------------------------------------------------- environment
def branch_of(path):
    """Branch name of a submodule; after `git clone --recursive` HEAD is detached,
    so fall back to the remote branch that points at it, then to .gitmodules."""
    b = run(["git", "branch", "--show-current"], cwd=path)
    if not b:
        refs = run(["git", "for-each-ref", "--points-at", "HEAD", "--format=%(refname:short)", "refs/remotes"], cwd=path)
        b = refs.split("\n")[0].replace("origin/", "") if refs else ""
    if not b:
        b = run(["git", "config", "-f", str(ROOT / ".gitmodules"), f"submodule.{path.name}.branch"])
    return b or "detached"


sail_head = run(["git", "log", "-1", "--format=%h %s"], cwd=ROOT / "sail-riscv")
sail_branch = branch_of(ROOT / "sail-riscv")
suite_head = run(["git", "log", "-1", "--format=%h %s"], cwd=ROOT / "rvp-test-suite")
suite_branch = branch_of(ROOT / "rvp-test-suite")
binutils_head = run(["git", "log", "-1", "--format=%h %s"], cwd=ROOT / "riscv-binutils")
as_ver = run([str(ROOT / "riscv-binutils/build/gas/as-new"), "--version"]).splitlines()[:1]
sail_ver = run(["sail", "--version"])

env = [
    ("Date", str(date.today())),
    ("Model under test", f"sail-riscv `{sail_branch}` — {sail_head}"),
    ("Simulator", "build/c_emulator/sail_riscv_sim (--enable-experimental-extensions, --test-signature)"),
    ("Sail", sail_ver or "n/a"),
    ("Run configs", "build/config/rv32d_v128_e32.json / rv64d_v128_e64.json"),
    ("Assembler", f"{as_ver[0] if as_ver else 'n/a'} — riscv-binutils {binutils_head}"),
    ("Test suite", f"rvp-test-suite `{suite_branch}` — {suite_head}"),
    ("Suite origin", "riscv_ctg (lab P templates) from per-instruction-group cgf files; riscv-arch-test TEST_* macros"),
    ("Method", "preprocess → assemble → link → execute on Sail; PASS = reached the HTIF exit (SUCCESS) "
               "with no illegal instruction; memory signature captured per test (granularity 4)"),
]

spec = [
    ("P specification", "RVP draft 020 (2026-03-21), https://www.jhauser.us/RISCV/ext-P/"),
    ("ISA (rv32)", "RV32IP_Zicsr_Zba_Zbb_Zbkb (tests borrow a few non-P instructions)"),
    ("ISA (rv64)", "RV64IP_Zicsr_Zba_Zbb_Zbkb"),
    ("Coverage definitions", "rvp-test-suite/rv32ip_cgf/*.cgf, rv64ip_cgf/*.cgf"),
]


def table(pairs):
    return "\n".join(
        f"<tr><td class='k'>{html.escape(k)}</td><td>{html.escape(str(v))}</td></tr>" for k, v in pairs
    )


result_rows = "\n".join(
    f"<tr class='{'ok' if v == 'PASS' else 'bad'}'>"
    f"<td>{i + 1}</td><td>{html.escape(n)}</td><td>{x}</td><td>{html.escape(v)}</td></tr>"
    for i, (n, x, v) in enumerate(rows)
)

summary_cells = " · ".join(f"{x}: {p}/{t}" for x, (t, p) in sorted(by_xlen.items()))

coverage_table = "\n".join(
    f"<tr><td>{x}</td><td>{a}</td><td>{b}</td><td>{c}</td></tr>" for x, a, b, c in coverage_rows
)
untested_html = "\n".join(
    f"<details><summary>{x}: {len(lst)} implemented mnemonics without a test</summary>"
    f"<p class='mono'>{html.escape(' '.join(lst)) if lst else '—'}</p></details>"
    for x, lst in untested_lists
)

OUT.write_text(f"""<!DOCTYPE html>
<html lang="en"><head><meta charset="utf-8"><title>RVP 020 Sail Test Report</title>
<style>
 body {{ font: 14px/1.5 -apple-system, Helvetica, Arial, sans-serif; margin: 2rem auto; max-width: 60rem; padding: 0 1rem; color: #222; }}
 h1 {{ border-bottom: 2px solid #333; padding-bottom: .3rem; }}
 table {{ border-collapse: collapse; width: 100%; margin: .6rem 0 1.4rem; }}
 td, th {{ border: 1px solid #ccc; padding: .25rem .6rem; text-align: left; vertical-align: top; }}
 th {{ background: #f0f0f0; }}
 td.k {{ width: 14rem; font-weight: 600; background: #f6f6f6; }}
 tr.ok td:last-child {{ color: #0a7a0a; font-weight: 600; }}
 tr.bad td:last-child {{ color: #b00020; font-weight: 700; }}
 .big {{ font-size: 1.25rem; font-weight: 700; }}
 .mono {{ font-family: ui-monospace, Menlo, monospace; font-size: 12px; word-break: break-word; }}
 details {{ margin: .4rem 0; }}
 p.note {{ color: #555; }}
</style></head><body>
<h1>RISC-V P Extension (RVP draft 020) — Sail Model Test Report</h1>

<h2>Environment</h2>
<table>{table(env)}</table>

<h2>Specification</h2>
<table>{table(spec)}</table>

<h2>Summary</h2>
<p class="big">{n_pass}/{len(rows)} PASS &nbsp; ({summary_cells})</p>
<p class="note">PASS means the test assembled, linked and ran to a clean exit on the model with no
illegal-instruction trap or trap loop. The memory signatures are captured per test and diffed
against <code>results/baseline/</code> to detect semantic drift between model versions; they are
produced by this model, not by an independent reference implementation.</p>

<h2>Coverage</h2>
<table>
<tr><th>XLEN</th><th>P mnemonics with at least one test</th><th>P mnemonics implemented in the model</th><th>implemented but untested</th></tr>
{coverage_table}
</table>
{untested_html}

<h2>Results</h2>
<table>
<tr><th>#</th><th>test</th><th>xlen</th><th>verdict</th></tr>
{result_rows}
</table>
</body></html>
""")
print(f"{OUT}: {n_pass}/{len(rows)} PASS ({summary_cells})")
for x, a, b, c in coverage_rows:
    print(f"  coverage {x}: {a}/{b} implemented mnemonics tested, {c} untested")
