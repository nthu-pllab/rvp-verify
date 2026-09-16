#!/usr/bin/env bash
# verify_insn.sh — self-check for one P-extension instruction against the
# CURRENT Sail model. Fast per-instruction verification while you implement/fix Sail.
#
# It checks two independent things:
#   ① ENCODING  — the P-aware binutils assembles `<mnem> a5,a3,a4`, and the Sail
#                 emulator decodes those exact bytes back to <mnem>. Catches wrong
#                 bits and two clauses claiming the same encoding.
#   ② SEMANTICS — for each `rs1,rs2 => expected` case you give, Sail must compute
#                 `expected` into rd. YOU supply `expected` from the P spec
#                 (https://www.jhauser.us/RISCV/ext-P/); this harness confirms Sail
#                 agrees. (The rvp-test-suite ships inputs but no golden outputs, so
#                 the spec — via you — is the source of truth here.)
#
# Usage:
#   ./verify_insn.sh <mnemonic> "<rs1>,<rs2>=><expected>" ["<rs1>,<rs2>=><expected>" ...]
#
#   Values are decimal or 0xHEX, negatives allowed (e.g. -0x80000000), compared as
#   XLEN-bit. Only the register-register form `rd,rs1,rs2` is supported in v1.
#
# Examples:
#   ./verify_insn.sh aadd "6,4=>5" "-0x80000000,0x7fffffff=>0xffffffff"
#   ./verify_insn.sh paadd.b "0x01020304,0x10203040=>0x08111922"   # averaging add
#
# Env overrides: XLEN (32|64, default 32), AS, LD, OD, SAIL, SAIL_CFG
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SAIL="${SAIL:-$ROOT/sail-riscv/build/c_emulator/sail_riscv_sim}"
XLEN="${XLEN:-32}"

AS="${AS:-$ROOT/riscv-binutils/build/gas/as-new}"
LD="${LD:-$ROOT/riscv-binutils/build/ld/ld-new}"
OD="${OD:-$ROOT/riscv-binutils/build/binutils/objdump}"

if [ "$XLEN" = 32 ]; then
  MARCH=rv32ip; MABI=ilp32; LDEMU="-m elf32lriscv"; W=8
  SAIL_CFG="${SAIL_CFG:-$ROOT/sail-riscv/build/config/rv32d_v128_e32.json}"
else
  MARCH=rv64ip; MABI=lp64;  LDEMU="";               W=16
  SAIL_CFG="${SAIL_CFG:-$ROOT/sail-riscv/build/config/rv64d_v128_e64.json}"
fi

# --- colors / helpers ---
if [ -t 1 ]; then G=$'\033[32m'; R=$'\033[31m'; Y=$'\033[33m'; B=$'\033[1m'; N=$'\033[0m'; else G= R= Y= B= N=; fi
die() { echo "${R}error:${N} $*" >&2; exit 2; }
[ $# -ge 1 ] || die "usage: $0 <mnemonic> \"rs1,rs2=>expected\" ..."
[ -x "$AS" ]   || die "P-aware as not found: $AS (build riscv-binutils, see README.md)"
[ -x "$SAIL" ] || die "Sail sim not found: $SAIL (run ./build.sh first)"

MNEM="$1"; shift
TMP="$(mktemp -d "${TMPDIR:-/tmp}/verify_insn.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

# normalize a numeric value to XLEN-bit lowercase hex (no 0x)
norm() {
  local v; v=$(( $1 )) || { echo "BADVAL"; return; }
  if [ "$XLEN" = 32 ]; then printf '%08x' $(( v & 0xffffffff ))
  else printf '%016x' "$v"; fi
}
# run a bare program on Sail, echo its full trace
run_sail() { # $1 = asm file
  "$AS" -march=$MARCH -mabi=$MABI "$1" -o "$TMP/p.o" 2>"$TMP/as.err" || return 1
  $LD $LDEMU -Ttext-segment=0x80000000 -e _start "$TMP/p.o" -o "$TMP/p.elf" 2>/dev/null || return 1
  "$SAIL" --config "$SAIL_CFG" --enable-experimental-extensions \
          --inst-limit 64 --trace-instr --trace-reg --use-abi-names "$TMP/p.elf" 2>&1
}

echo "${B}== verify $MNEM  (rv$XLEN, Sail model) ==${N}"

# ---------- ① ENCODING: binutils assembles it, Sail decodes it back ----------
cat > "$TMP/enc.s" <<EOF
.section .text.init
.global _start
_start:
  $MNEM a5,a3,a4
1: j 1b
EOF
if ! "$AS" -march=$MARCH -mabi=$MABI "$TMP/enc.s" -o "$TMP/enc.o" 2>"$TMP/as.err"; then
  echo "${R}✗ ENCODING${N}  binutils can't assemble '$MNEM':"
  sed 's/^/    /' "$TMP/as.err"; exit 1
fi
HEX=$("$OD" -d "$TMP/enc.o" | awk -F'\t' '/^ *0:/{gsub(/ /,"",$2);print $2;exit}')
$LD $LDEMU -Ttext-segment=0x80000000 -e _start "$TMP/enc.o" -o "$TMP/enc.elf" 2>/dev/null
DEC=$("$SAIL" --config "$SAIL_CFG" --enable-experimental-extensions --inst-limit 2 \
      --trace-instr "$TMP/enc.elf" 2>&1 | grep -iE "\(0x$HEX\)" | head -1 \
      | sed -E 's/.*\(0x[0-9A-Fa-f]+\) //; s/ .*//')
if [ "$DEC" = "$MNEM" ]; then
  echo "${G}✓ ENCODING${N}  0x$HEX  binutils=$MNEM  ↔  Sail=$DEC"
elif [ -z "$DEC" ] || [ "$DEC" = "illegal" ]; then
  echo "${R}✗ ENCODING${N}  0x$HEX  binutils=$MNEM  but Sail=${R}illegal${N}  (wrong bits or shadowed by another clause)"
  exit 1
else
  echo "${R}✗ ENCODING${N}  0x$HEX  binutils=$MNEM  but Sail decodes it as ${R}$DEC${N}  (encoding collision)"
  exit 1
fi

# ---------- ② SEMANTICS: run each case, check rd ----------
pass=0; fail=0
[ $# -gt 0 ] || echo "${Y}  (no semantic cases given — encoding only)${N}"
for case in "$@"; do
  in="${case%%=>*}"; exp="${case##*=>}"
  rs1="${in%%,*}"; rs2="${in##*,}"
  [ "$in" != "$case" ] && [ "$rs1" != "$in" ] || die "bad case '$case' (want rs1,rs2=>expected)"
  want=$(norm "$exp"); [ "$want" = "BADVAL" ] && die "bad expected value in '$case'"

  cat > "$TMP/sem.s" <<EOF
.section .text.init
.global _start
_start:
  li a3, $rs1
  li a4, $rs2
  $MNEM a5,a3,a4
1: j 1b
EOF
  trace=$(run_sail "$TMP/sem.s") || { echo "${R}✗${N} $rs1,$rs2  (assemble/link failed)"; fail=$((fail+1)); continue; }
  got=$(printf '%s' "$trace" | grep -E "a5 <-" | tail -1 | grep -oiE "0x[0-9a-f]+" | head -1 | sed 's/^0[xX]//' | tr 'A-F' 'a-f')
  if [ -z "$got" ]; then
    printf "${R}✗${N} %-22s %s => a5 was never written (illegal instruction, or the program did not reach it)\n" "$rs1,$rs2" "$MNEM"
    fail=$((fail+1)); continue
  fi
  got=$(printf '%0*s' "$W" "$got" | tr ' ' '0')   # pad
  if [ "$got" = "$want" ]; then
    printf "${G}✓${N} %-22s %s => got 0x%s\n" "$rs1,$rs2" "$MNEM" "$got"
    pass=$((pass+1))
  else
    printf "${R}✗${N} %-22s %s => got 0x%s  ${R}expected 0x%s${N}\n" "$rs1,$rs2" "$MNEM" "$got" "$want"
    fail=$((fail+1))
  fi
done

echo "${B}-- $MNEM: encoding ✓, semantics $pass/$((pass+fail)) --${N}"
[ "$fail" -eq 0 ]
