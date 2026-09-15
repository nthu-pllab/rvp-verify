#!/usr/bin/env bash
# regen_tests.sh — regenerate rvp-test-suite tests from their cgf pages.
#
# Usage:
#   ./regen_tests.sh rv32 p20 [outdir]     # one page
#   ./regen_tests.sh rv64 p6-7 [outdir]
#
# Output .S files land in <outdir> (default: ./regen_out/<xlen>_<page>).
# Copy the ones you want into rvp-test-suite/<suite>/test_*/ by hand —
# regeneration is per-page, adoption into the suite is a reviewed decision.
#
# Needs the venv from ./setup_ctg_venv.sh. dataset.cgf must come first on the
# ctg command line: the page cgfs reference YAML anchors it defines.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV=$ROOT/ctg-venv
DATASET=$ROOT/coverage/dataset.cgf

xlen=${1:?usage: regen_tests.sh rv32|rv64 pN [outdir]}
page=${2:?usage: regen_tests.sh rv32|rv64 pN [outdir]}
case $xlen in
  rv32) bi=rv32i; cgf=$ROOT/rvp-test-suite/rv32ip_cgf/$page.cgf ;;
  rv64) bi=rv64i; cgf=$ROOT/rvp-test-suite/rv64ip_cgf/$page.cgf ;;
  *) echo "xlen must be rv32 or rv64" >&2; exit 2 ;;
esac
[ -f "$cgf" ] || { echo "no such cgf: $cgf" >&2; exit 2; }
out=${3:-$PWD/regen_out/${xlen}_${page}}
mkdir -p "$out"

"$VENV/bin/riscv_ctg" -bi "$bi" -cf "$DATASET" -cf "$cgf" -d "$out" -v info --procs 8
echo; echo "generated into: $out"; ls "$out"/*.S 2>/dev/null | wc -l
