# tests/scripts/test_historical_blend.sh
#!/usr/bin/env bash
set -euo pipefail
export CLAUDE_PLUGIN_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

tmpdir=$(mktemp -d)
GD="$tmpdir/global"
mkdir -p "$GD"
cat > "$GD/merge_outcomes.jsonl" <<'EOF'
{"repo":"apache/airflow","outcome":"merged","closed_at":"2026-04-01T00:00:00Z"}
{"repo":"apache/airflow","outcome":"merged","closed_at":"2026-04-15T00:00:00Z"}
{"repo":"apache/airflow","outcome":"closed_no_merge","closed_at":"2026-05-01T00:00:00Z"}
EOF

out=$(bash "$CLAUDE_PLUGIN_ROOT/scripts/scorer/historical_blend.sh" \
        --rubric-01 0.72 \
        --merge-log "$GD/merge_outcomes.jsonl" \
        --repo apache/airflow \
        --weight 0.3)

# 2/3 merged + Laplace smoothing → est ~0.6, blend = 0.7 * 0.72 + 0.3 * ~0.6 ≈ 0.684
final=$(echo "$out" | jq -r .blended)
# Must be a finite number 0..10
echo "$out" | jq -e '.blended | type == "number"' >/dev/null || { echo "FAIL not number"; exit 1; }
awk -v v="$final" 'BEGIN{ if (v<0||v>10) exit 1; }' || { echo "FAIL out of range: $final"; exit 1; }

echo "OK test_historical_blend.sh"
