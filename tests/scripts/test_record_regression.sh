#!/usr/bin/env bash
set -euo pipefail
export CLAUDE_PLUGIN_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
source "$CLAUDE_PLUGIN_ROOT/scripts/lib/state.sh"
RR="$CLAUDE_PLUGIN_ROOT/scripts/lessons/record_regression.sh"
SCHEMA="$CLAUDE_PLUGIN_ROOT/schemas/lesson_regression.schema.json"
tmpdir=$(mktemp -d)
TS="2026-07-04T00:00:00Z"

# Redirect state to a temp HOME so we never touch real ~/.superhuman.
export HOME="$tmpdir"
log="$tmpdir/.superhuman/global/lesson_regressions.jsonl"

# --- valid append writes one schema-valid line ---
bash "$RR" --repo apache/airflow --rule-id apache-airflow-newsfragment --kind shipped_violation --pr-url "https://github.com/apache/airflow/pull/1" --ts "$TS"
[ -f "$log" ] || { echo "FAIL log not created"; exit 1; }
[ "$(wc -l < "$log" | tr -d ' ')" -eq 1 ] || { echo "FAIL should have 1 line"; exit 1; }
jq -c 'select(.rule_id=="apache-airflow-newsfragment" and .kind=="shipped_violation" and .repo=="apache/airflow" and .ts=="'"$TS"'")' "$log" | grep -q . || { echo "FAIL line content wrong"; exit 1; }
head -1 "$log" > "$tmpdir/line.json"
validate_json "$SCHEMA" "$tmpdir/line.json" || { echo "FAIL line must validate against lesson_regression schema"; exit 1; }

# --- append is additive (second kind) ---
bash "$RR" --repo apache/airflow --rule-id apache-airflow-newsfragment --kind maintainer_reraise --ts "$TS"
[ "$(wc -l < "$log" | tr -d ' ')" -eq 2 ] || { echo "FAIL should append, not overwrite"; exit 1; }

# --- unknown --kind rejected with exit 2 ---
set +e
bash "$RR" --repo apache/airflow --rule-id x --kind bogus --ts "$TS" 2>/dev/null; rc=$?
set -e
[ "$rc" -eq 2 ] || { echo "FAIL unknown kind must exit 2, got $rc"; exit 1; }
[ "$(wc -l < "$log" | tr -d ' ')" -eq 2 ] || { echo "FAIL rejected call must not write"; exit 1; }

# --- missing --rule-id rejected ---
set +e
bash "$RR" --repo apache/airflow --kind shipped_violation --ts "$TS" 2>/dev/null; rc=$?
set -e
[ "$rc" -eq 2 ] || { echo "FAIL missing rule-id must exit 2, got $rc"; exit 1; }

echo "OK test_record_regression.sh"
