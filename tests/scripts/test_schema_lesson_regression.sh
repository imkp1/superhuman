#!/usr/bin/env bash
set -euo pipefail
export CLAUDE_PLUGIN_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
source "$CLAUDE_PLUGIN_ROOT/scripts/lib/state.sh"
SCHEMA="$CLAUDE_PLUGIN_ROOT/schemas/lesson_regression.schema.json"
tmpdir=$(mktemp -d)
cat > "$tmpdir/ok.json" <<'EOF'
{"rule_id":"apache-airflow-newsfragment","repo":"apache/airflow","pr_url":"https://github.com/apache/airflow/pull/1","kind":"shipped_violation","ts":"2026-07-03T00:00:00Z"}
EOF
validate_json "$SCHEMA" "$tmpdir/ok.json" || { echo "FAIL valid regression rejected"; exit 1; }
echo '{"rule_id":"x","repo":"a/b"}' > "$tmpdir/bad.json"
validate_json "$SCHEMA" "$tmpdir/bad.json" 2>/dev/null && { echo "FAIL regression missing kind/ts accepted"; exit 1; }
echo "OK test_schema_lesson_regression.sh"
