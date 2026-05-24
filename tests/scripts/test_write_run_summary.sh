# tests/scripts/test_write_run_summary.sh
#!/usr/bin/env bash
set -euo pipefail
export CLAUDE_PLUGIN_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

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

echo "OK test_write_run_summary.sh"
