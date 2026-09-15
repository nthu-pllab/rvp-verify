#!/usr/bin/env bash
# setup_ctg_venv.sh — build the riscv_ctg venv used to (re)generate rvp-test-suite tests.
#
# Idempotent: safe to rerun; rebuilds from scratch with --fresh.
# The venv itself is disposable — this script IS the source of truth for it.
#
# What it does, and why each step exists:
#   1. venv + pip install of the LAB riscv-ctg (./riscv-ctg, the only ctg with
#      P support: p.yaml + dsp_function.py).
#   2. Copies env/arch-test into the installed package — setup.py's
#      package_data misses it and ctg's startup copytree(const.env) dies without it.
#   3. Patches the installed riscv_isac's utils.py with yaml.width = 65536:
#      load_cgf() round-trips cgf through a dump/reload and modern ruamel wraps
#      long coverpoint keys at 80 cols, corrupting them (unparseable on reload).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV=$ROOT/ctg-venv
CTG_SRC=$ROOT/riscv-ctg
ENV_SRC=$ROOT/env/arch-test

[ "${1:-}" = "--fresh" ] && rm -rf "$VENV"

python3 -m venv "$VENV"
"$VENV/bin/pip" install --quiet --force-reinstall "$CTG_SRC"

SITE_CTG=$("$VENV/bin/python" -c "import riscv_ctg, pathlib; print(pathlib.Path(riscv_ctg.__file__).parent)")
SITE_ISAC=$("$VENV/bin/python" -c "import riscv_isac, pathlib; print(pathlib.Path(riscv_isac.__file__).parent)")

# 2. env folder the installer forgot
rm -rf "$SITE_CTG/env"
cp -r "$ENV_SRC" "$SITE_CTG/env"

# 3. ruamel line-wrap fix (idempotent)
if ! grep -q "width = 65536" "$SITE_ISAC/utils.py"; then
  "$VENV/bin/python" - "$SITE_ISAC/utils.py" <<'EOF'
import sys, re
p = sys.argv[1]
s = open(p).read()
s = re.sub(r'^(yaml = YAML\(typ="rt"\))$',  r'\1\nyaml.width = 65536',      s, count=1, flags=re.M)
s = re.sub(r'^(safe_yaml = YAML\(typ="safe"\))$', r'\1\nsafe_yaml.width = 65536', s, count=1, flags=re.M)
assert s.count("width = 65536") == 2, "utils.py layout changed; patch manually"
open(p, "w").write(s)
EOF
fi

"$VENV/bin/riscv_ctg" --version
echo "ok: $VENV"
