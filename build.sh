#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
python3 "$ROOT/tests/test_sim.py"
python3 "$ROOT/tests/test_compiler.py"
python3 "$ROOT/tests/test_sim_ctrl.py"
python3 "$ROOT/tests/test_differential.py"
echo "Pre-RTL software/golden tests passed. RTL/bitstream build is intentionally not implemented yet."
