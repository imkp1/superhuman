#!/usr/bin/env bash
# telemetry_optout.sh [--on]
# Persistently disable (default) or re-enable superhuman adoption telemetry
# by writing the enabled flag that usage_ping.sh honors.
set -euo pipefail
GLOBAL_DIR="$HOME/.superhuman/global"
FLAG_FILE="$GLOBAL_DIR/telemetry.json"
mkdir -p "$GLOBAL_DIR"
if [ "${1:-}" = "--on" ]; then
  printf '{"enabled":true}\n' > "$FLAG_FILE"
  echo "superhuman telemetry: enabled"
else
  printf '{"enabled":false}\n' > "$FLAG_FILE"
  echo "superhuman telemetry: disabled"
fi
