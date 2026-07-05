#!/usr/bin/env bash
# tests/scripts/test_pr_body_with_attribution.sh
set -euo pipefail
export CLAUDE_PLUGIN_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT="$CLAUDE_PLUGIN_ROOT/scripts/orchestrator/pr_body_with_attribution.sh"

fail() { echo "FAIL: $1"; exit 1; }

BASE='## Summary
Fixes the thing.'

# 1. Default (unset): footer appended, base body preserved, repo url present.
unset SUPERHUMAN_ATTRIBUTION 2>/dev/null || true
OUT="$(printf '%s' "$BASE" | bash "$SCRIPT")"
printf '%s' "$OUT" | grep -qF 'Opened with [Superhuman]'        || fail "default: footer missing"
printf '%s' "$OUT" | grep -qF 'Fixes the thing.'                || fail "default: base body lost"
printf '%s' "$OUT" | grep -qF 'github.com/gaurav0107/superhuman' || fail "default: repo url missing"

# 2. Disabling values suppress the footer and return the body byte-for-byte.
for v in off OFF false 0 no; do
  OUT="$(printf '%s' "$BASE" | SUPERHUMAN_ATTRIBUTION="$v" bash "$SCRIPT")"
  [ "$OUT" = "$BASE" ] || fail "disable '$v': body not returned verbatim"
done

# 3. Idempotency: a body that already carries the footer is unchanged, marker once.
WITH_FOOTER="$(printf '%s' "$BASE" | bash "$SCRIPT")"
AGAIN="$(printf '%s' "$WITH_FOOTER" | bash "$SCRIPT")"
[ "$AGAIN" = "$WITH_FOOTER" ] || fail "idempotency: output changed on second pass"
COUNT="$(printf '%s' "$AGAIN" | grep -cF 'Opened with [Superhuman]')"
[ "$COUNT" = "1" ] || fail "idempotency: marker count = $COUNT (want 1)"

echo "OK test_pr_body_with_attribution.sh"
