# tests/scripts/test_write_run_summary.sh
#!/usr/bin/env bash
set -euo pipefail
export CLAUDE_PLUGIN_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
export SUPERHUMAN_TELEMETRY=off   # keep telemetry wiring from hitting the network in tests

tmpdir=$(mktemp -d)
HOME="$tmpdir" bash "$CLAUDE_PLUGIN_ROOT/scripts/orchestrator/write_run_summary.sh" \
  --repo apache/airflow --outcome merge_ready --iterations 4 \
  --pr-url https://github.com/apache/airflow/pull/66010 \
  --completed-at 2026-05-06T04:31:00Z --exit-reason normal

OUT="$tmpdir/.superhuman/repos/apache-airflow/run_summary.json"
[ -f "$OUT" ] || { echo "FAIL no file"; exit 1; }
jq -e '.outcome=="merge_ready"' "$OUT" >/dev/null     || { echo "FAIL outcome"; exit 1; }
jq -e '.exit_reason=="normal"' "$OUT" >/dev/null     || { echo "FAIL exit_reason"; exit 1; }

# Crash path: minimal args
HOME="$tmpdir" bash "$CLAUDE_PLUGIN_ROOT/scripts/orchestrator/write_run_summary.sh" \
  --repo b/b --outcome crash --exit-reason "uncaught:flock-timeout" \
  --completed-at 2026-05-06T04:31:00Z
OUT2="$tmpdir/.superhuman/repos/b-b/run_summary.json"
jq -e '.outcome=="crash"' "$OUT2" >/dev/null || { echo "FAIL crash outcome"; exit 1; }

# --- telemetry wiring: run_summary is still written and exit stays clean ---
HOME="$tmpdir" bash "$CLAUDE_PLUGIN_ROOT/scripts/orchestrator/write_run_summary.sh" \
  --repo o/r --outcome merged_ready --iterations 2 \
  --pr-url https://github.com/o/r/pull/1 \
  --completed-at 2026-07-05T00:00:00Z --exit-reason done
jq -e '.outcome=="merged_ready"' "$tmpdir/.superhuman/repos/o-r/run_summary.json" >/dev/null \
  || { echo "FAIL: telemetry wiring broke run_summary"; exit 1; }

echo "OK test_write_run_summary.sh"
