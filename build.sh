#!/usr/bin/env bash
# build.sh — build the two tools the scripts need, in place inside the submodules:
#   riscv-binutils/build/{gas/as-new, ld/ld-new, binutils/objdump}   (P-aware binutils)
#   sail-riscv/build/c_emulator/sail_riscv_sim                        (Sail model)
#
# Usage:  ./build.sh            # incremental (skips binutils if already built)
#         ./build.sh --fresh    # reconfigure + rebuild both from scratch
#         JOBS=4 ./build.sh
#
# Prereqs: git submodules checked out (git submodule update --init), a C/C++
# toolchain, cmake, and Sail 0.20.2 on PATH (opam install sail.0.20.2 && eval $(opam env)).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
JOBS=${JOBS:-8}
FRESH=0; [ "${1:-}" = "--fresh" ] && FRESH=1

for sub in riscv-binutils sail-riscv rvp-test-suite; do
  [ -e "$ROOT/$sub/.git" ] || { echo "submodule $sub not checked out: run 'git submodule update --init'" >&2; exit 2; }
done

# --- binutils ---
BU="$ROOT/riscv-binutils/build"
if [ $FRESH = 1 ]; then rm -rf "$BU"; fi
if [ ! -x "$BU/gas/as-new" ] || [ ! -x "$BU/ld/ld-new" ]; then
  echo "== building riscv-binutils"
  mkdir -p "$BU"; cd "$BU"
  [ -f Makefile ] || ../configure --target=riscv64-unknown-elf --disable-gdb --disable-sim \
      --disable-gprofng --disable-werror --disable-nls --with-system-zlib
  make -j"$JOBS"
  cd "$ROOT"
else
  echo "== riscv-binutils already built ($BU/gas/as-new)"
fi

# --- sail-riscv ---
command -v sail >/dev/null || { echo "sail not on PATH: opam install sail.0.20.2 && eval \$(opam env)" >&2; exit 2; }
SR="$ROOT/sail-riscv"
if [ $FRESH = 1 ]; then rm -rf "$SR/build"; fi
# upstream's gdbserver pulls asio 1.36.0 from sourceforge, which sometimes
# answers 403. Set ASIO_SRC to a local unpacked asio tree (the `asio/` dir
# containing include/asio.hpp, e.g. from
# https://github.com/chriskohlhoff/asio/archive/refs/tags/asio-1-36-0.tar.gz)
# to skip the download.
if [ ! -f "$SR/build/CMakeCache.txt" ]; then
  echo "== building sail-riscv (first time)"
  cmake -S "$SR" -B "$SR/build" -DCMAKE_BUILD_TYPE=RelWithDebInfo \
      -DDOWNLOAD_GMP=TRUE -DENABLE_RISCV_TESTS=TRUE \
      ${ASIO_SRC:+-DFETCHCONTENT_SOURCE_DIR_ASIO="$ASIO_SRC"}
  cmake --build "$SR/build" -j"$JOBS"
else
  echo "== rebuilding sail-riscv (incremental)"
  cmake --build "$SR/build" -j"$JOBS"
fi

echo
echo "ok:"
echo "  $BU/gas/as-new"
echo "  $BU/ld/ld-new"
echo "  $SR/build/c_emulator/sail_riscv_sim"
