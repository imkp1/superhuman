# tests/scripts/test_iteration_cap.sh
#!/usr/bin/env bash
set -euo pipefail
export CLAUDE_PLUGIN_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

[ "$(bash "$CLAUDE_PLUGIN_ROOT/scripts/orchestrator/iteration_cap.sh" --loc 0)"   = "3" ]  || { echo "FAIL 0";   exit 1; }
[ "$(bash "$CLAUDE_PLUGIN_ROOT/scripts/orchestrator/iteration_cap.sh" --loc 50)"  = "3" ]  || { echo "FAIL 50";  exit 1; }
[ "$(bash "$CLAUDE_PLUGIN_ROOT/scripts/orchestrator/iteration_cap.sh" --loc 51)"  = "6" ]  || { echo "FAIL 51";  exit 1; }
[ "$(bash "$CLAUDE_PLUGIN_ROOT/scripts/orchestrator/iteration_cap.sh" --loc 200)" = "6" ]  || { echo "FAIL 200"; exit 1; }
[ "$(bash "$CLAUDE_PLUGIN_ROOT/scripts/orchestrator/iteration_cap.sh" --loc 201)" = "10" ] || { echo "FAIL 201"; exit 1; }
[ "$(bash "$CLAUDE_PLUGIN_ROOT/scripts/orchestrator/iteration_cap.sh" --loc 9999)" = "10" ]|| { echo "FAIL big"; exit 1; }
echo "OK test_iteration_cap.sh"
