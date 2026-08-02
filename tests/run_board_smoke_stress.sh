#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 5 ]]; then
  echo "usage: $0 <bdf> <xclbin> <device-index> <aecbin> <duration-seconds>" >&2
  exit 2
fi

bdf="$1"
xclbin="$2"
device_index="$3"
aecbin="$4"
duration_seconds="$5"
root_dir="$(cd "$(dirname "$0")/.." && pwd)"
log_dir="${root_dir}/reports/board_smoke_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$log_dir"

thermal_pid=""
cleanup() {
  if [[ -n "$thermal_pid" ]]; then
    kill "$thermal_pid" 2>/dev/null || true
    wait "$thermal_pid" 2>/dev/null || true
  fi
}
trap cleanup EXIT INT TERM

xbutil examine -d "$bdf" -r platform | tee "$log_dir/platform.log"
xbutil examine -d "$bdf" -r memory | tee "$log_dir/memory.log"
xbutil examine -d "$bdf" -r thermal | tee "$log_dir/thermal_before.log"
xbutil examine -d "$bdf" -r electrical | tee "$log_dir/electrical_before.log"

(
  while true; do
    date --iso-8601=seconds
    xbutil examine -d "$bdf" -r thermal
    xbutil examine -d "$bdf" -r electrical
    sleep 60
  done
) >> "$log_dir/thermal_electrical.log" 2>&1 &
thermal_pid="$!"

"${root_dir}/driver/aec_board_smoke" "$xclbin" "$device_index" "$aecbin" \
  --duration-seconds "$duration_seconds" | tee "$log_dir/smoke.log"

xbutil examine -d "$bdf" -r thermal | tee "$log_dir/thermal_after.log"
xbutil examine -d "$bdf" -r electrical | tee "$log_dir/electrical_after.log"
