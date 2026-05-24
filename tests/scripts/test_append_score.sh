# tests/scripts/test_append_score.sh
#!/usr/bin/env bash
set -euo pipefail
export CLAUDE_PLUGIN_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

tmpdir=$(mktemp -d)
SD="$tmpdir/.superhuman/repos/apache-airflow"
mkdir -p "$SD"
cat > "$SD/current_contribution.json" <<'EOF'
{"repo":"apache/airflow","issue_number":1,"branch":"x","iteration":0,
 "scores":[],"lock_holder":"opensource-contributor","started_at":"2026-04-24T11:00:00Z"}
EOF

SCORE_BLOB='{"iteration":1,"ts":"2026-04-24T11:15:00Z",
             "dimensions":{"correctness":7},"raw":78,"final":72,
             "plateaued":[],"caps_applied":["process"]}'

HOME="$tmpdir" bash "$CLAUDE_PLUGIN_ROOT/scripts/scorer/append_score.sh" \
  --repo apache/airflow --score "$SCORE_BLOB"

count=$(jq '.scores | length' "$SD/current_contribution.json")
[ "$count" = "1" ]   || { echo "FAIL count: $count"; exit 1; }
final=$(jq '.scores[0].final' "$SD/current_contribution.json")
[ "$final" = "72" ]  || { echo "FAIL final: $final"; exit 1; }

echo "OK test_append_score.sh"
