#!/usr/bin/env bash
# run_suite.sh — run the 020-named rvp-test-suite on the Sail model.
#
# Pipeline per test: gcc -E (macros from env/) → P-aware as → ld →
# sail_riscv_sim with --test-signature.
# Verdicts: PASS / PP_FAIL / AS_FAIL / LD_FAIL / TIMEOUT / INST_LIMIT / RUN_FAIL(rc=N)
#
# Usage:  LIMIT=2 bash run_suite.sh   # smoke: 2 tests per suite
#         bash run_suite.sh           # full (446 rv32 + 318 rv64)
#
# Prereqs: see README.md (build riscv-binutils and sail-riscv submodules,
# riscv64-unknown-elf-gcc in PATH or RISCV_GCC set).
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AS=${AS:-$ROOT/riscv-binutils/build/gas/as-new}
LD=${LD:-$ROOT/riscv-binutils/build/ld/ld-new}
GCC=${RISCV_GCC:-${RISCV:+$RISCV/bin/riscv64-unknown-elf-gcc}}
GCC=${GCC:-$(command -v riscv64-unknown-elf-gcc || true)}
SAILDIR=${SAILDIR:-$ROOT/sail-riscv}
SAIL=${SAIL:-$SAILDIR/build/c_emulator/sail_riscv_sim}
PENV=$ROOT/env/sail                         # model_test.h + link.ld
AENV=$ROOT/env/arch-test                    # arch_test.h + test_macros.h
OUT=${OUT:-$ROOT/results/current}
LIMIT=${LIMIT:-0}
INST_LIMIT=${INST_LIMIT:-4000000}

[ -n "$GCC" ] || { echo "riscv64-unknown-elf-gcc not found; set RISCV_GCC" >&2; exit 2; }
for f in "$AS" "$LD" "$GCC" "$SAIL" "$PENV/link.ld" "$AENV/arch_test.h"; do
  [ -e "$f" ] || { echo "missing: $f (see README.md build steps)" >&2; exit 2; }
done
mkdir -p "$OUT"; : > "$OUT/results.tsv"
T="$OUT/tmp"; mkdir -p "$T"

scan_suite() { # $1=suite dir  $2=xlen
  local suite=$1 xlen=$2 march mabi ldemu cfg
  if [ "$xlen" = 32 ]; then
    march=rv32ip_zicsr_zba_zbb_zbkb; ppmarch=rv32i; mabi=ilp32; ldemu="-m elf32lriscv"
    cfg=$SAILDIR/build/config/rv32d_v128_e32.json
  else
    march=rv64ip_zicsr_zba_zbb_zbkb; ppmarch=rv64i; mabi=lp64; ldemu=""
    cfg=$SAILDIR/build/config/rv64d_v128_e64.json
  fi
  local total n=0
  total=$(find "$suite" -name '*.S' ! -path '*/env/*' | wc -l | tr -d ' ')
  find "$suite" -name '*.S' ! -path '*/env/*' | sort | while read -r src; do
    n=$((n+1))
    [ "$LIMIT" -gt 0 ] && [ "$n" -gt "$LIMIT" ] && break
    local name page id verdict rc
    name=$(basename "$src" .S)
    page=$(basename "$(dirname "$src")")
    # tests with the same name exist on several spec pages: key files by page too
    id="${page}_${name}"
    rm -f "$T"/t.*
    if ! "$GCC" -E -march=$ppmarch -mabi=$mabi -DXLEN=$xlen -DTEST_CASE_1=True -I "$PENV" -I "$AENV" "$src" -o "$T/t.pp.s" 2>"$T/t.err"; then
      verdict=PP_FAIL
    elif ! "$AS" -march=$march -mabi=$mabi "$T/t.pp.s" -o "$T/t.o" 2>"$T/t.err"; then
      verdict=AS_FAIL
    elif ! "$LD" $ldemu -T "$PENV/link.ld" "$T/t.o" -o "$T/t.elf" 2>"$T/t.err"; then
      verdict=LD_FAIL
    else
      timeout 90 "$SAIL" --config "$cfg" --enable-experimental-extensions \
        --test-signature "$T/t.sig" --signature-granularity 4 \
        --inst-limit "$INST_LIMIT" "$T/t.elf" >"$T/t.log" 2>&1
      rc=$?
      # The simulator prints SUCCESS when the test reaches the HTIF exit. It
      # also exits 0 when the instruction limit runs out, so the exit code
      # alone is not enough to call a test passed.
      if grep -q '^SUCCESS' "$T/t.log"; then verdict=PASS
      elif [ $rc -eq 124 ]; then verdict=TIMEOUT
      elif [ $rc -eq 0 ];   then verdict=INST_LIMIT
      else verdict="RUN_FAIL(rc=$rc)"; fi
    fi
    printf '%s/%s\trv%s\t%s\n' "$page" "$name" "$xlen" "$verdict" >> "$OUT/results.tsv"
    if [ "$verdict" = PASS ]; then
      printf '[%3d/%s rv%s] %-34s PASS\n' "$n" "$total" "$xlen" "$page/$name"
    else
      printf '[%3d/%s rv%s] %-34s ** %s **\n' "$n" "$total" "$xlen" "$page/$name" "$verdict"
      [ -s "$T/t.err" ] && cp "$T/t.err" "$OUT/fail_rv${xlen}_${id}.err"
      [ -s "$T/t.log" ] && cp "$T/t.log" "$OUT/fail_rv${xlen}_${id}.log"
    fi
    # keep the signature for later coverage/diff use
    [ -s "$T/t.sig" ] && cp "$T/t.sig" "$OUT/sig_rv${xlen}_${id}.sig"
  done
}

scan_suite "$ROOT/rvp-test-suite/rv32ip-suite" 32
scan_suite "$ROOT/rvp-test-suite/rv64ip-suite" 64

echo
echo "════════ SUMMARY ════════"
cut -f3 "$OUT/results.tsv" | sed 's/(rc=[0-9]*)//' | sort | uniq -c | sort -rn
for x in 32 64; do
  p=$(awk -F'\t' -v x="rv$x" '$2==x && $3=="PASS"' "$OUT/results.tsv" | wc -l | tr -d ' ')
  t=$(awk -F'\t' -v x="rv$x" '$2==x' "$OUT/results.tsv" | wc -l | tr -d ' ')
  echo "  rv$x: $p/$t PASS"
done
echo "details: $OUT/results.tsv"
