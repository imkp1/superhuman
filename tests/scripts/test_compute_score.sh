# tests/scripts/test_compute_score.sh
#!/usr/bin/env bash
set -euo pipefail
export CLAUDE_PLUGIN_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

# 10 dims at known scores → weighted sum verified against spec weights
# Weights: Correctness 22, Tests 18, Historical 10, Style/PR/Process/Scope 9 each, Docs/Commit 5 each, Risk 4
DIMS='{"correctness":10,"test_coverage":10,"style":10,"pr_format":10,"process":10,
       "scope":10,"docs":10,"commit":10,"risk":10,"historical":10}'

out=$(bash "$CLAUDE_PLUGIN_ROOT/scripts/scorer/compute_score.sh" \
        --dimensions "$DIMS" --caps-applied '[]' --plateaued '[]')
raw=$(echo "$out" | jq -r .raw)
final=$(echo "$out" | jq -r .final)
[ "$raw" = "100" ]   || { echo "FAIL raw at all-10: $raw"; exit 1; }
[ "$final" = "100" ] || { echo "FAIL final at all-10: $final"; exit 1; }

# Process cap applied → final clamped at 50
out=$(bash "$CLAUDE_PLUGIN_ROOT/scripts/scorer/compute_score.sh" \
        --dimensions "$DIMS" --caps-applied '["process"]' --plateaued '[]')
final=$(echo "$out" | jq -r .final)
[ "$final" = "50" ] || { echo "FAIL process cap: $final"; exit 1; }

# CI-health cap applied → final clamped at 40
out=$(bash "$CLAUDE_PLUGIN_ROOT/scripts/scorer/compute_score.sh" \
        --dimensions "$DIMS" --caps-applied '["ci_health"]' --plateaued '[]')
final=$(echo "$out" | jq -r .final)
[ "$final" = "40" ] || { echo "FAIL ci_health cap: $final"; exit 1; }

echo "OK test_compute_score.sh"
