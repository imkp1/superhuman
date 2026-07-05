#!/usr/bin/env bash
# tests/scripts/test_telemetry_optout.sh
set -euo pipefail
export CLAUDE_PLUGIN_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT="$CLAUDE_PLUGIN_ROOT/scripts/lib/telemetry_optout.sh"
TMP=$(mktemp -d); export HOME="$TMP"

bash "$SCRIPT"
grep -q '"enabled":false' "$HOME/.superhuman/global/telemetry.json" \
  || { echo "FAIL: default should disable"; exit 1; }

bash "$SCRIPT" --on
grep -q '"enabled":true' "$HOME/.superhuman/global/telemetry.json" \
  || { echo "FAIL: --on should enable"; exit 1; }

rm -rf "$TMP"
echo "OK test_telemetry_optout.sh"
