#!/usr/bin/env bash
set -euo pipefail
export CLAUDE_PLUGIN_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
source "$CLAUDE_PLUGIN_ROOT/scripts/lib/state.sh"
SS="$CLAUDE_PLUGIN_ROOT/scripts/lessons/set_lesson_status.sh"
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT
STORE="$tmpdir/lessons.jsonl"

# two active cards
cat > "$STORE" <<'JSON'
{"id":"a-tests-location","scope":"repo","match":{"repo":"a/b"},"kind":"semantic","rule":"tests under tests/","source":"scan","evidence":["seed"],"confidence":0.8,"hits":3,"repos_seen":["a/b"],"status":"active","created":"2026-01-01T00:00:00Z","last_confirmed":"2026-01-01T00:00:00Z"}
{"id":"a-newsfragment","scope":"repo","match":{"repo":"a/b"},"kind":"deterministic","check":{"id":"file_present","args":{"glob":"newsfragments/**"}},"rule":"add a newsfragment","source":"comment","evidence":["pr#5"],"confidence":0.9,"hits":4,"repos_seen":["a/b"],"status":"active","created":"2026-01-01T00:00:00Z","last_confirmed":"2026-01-01T00:00:00Z"}
JSON

# --- demote one card, lower confidence, cite a reason ---
bash "$SS" --store "$STORE" --card-id a-newsfragment --status demoted --confidence 0.3 \
  --reason "maintainer: newsfragments not required for docs-only PRs (pr#9)" --now 2026-07-05T00:00:00Z

[ "$(jq -r 'select(.id=="a-newsfragment").status' "$STORE")" = "demoted" ] || { echo "FAIL demote should set status=demoted"; exit 1; }
[ "$(jq -r 'select(.id=="a-newsfragment").confidence' "$STORE")" = "0.3" ] || { echo "FAIL demote should override confidence"; exit 1; }
jq -e 'select(.id=="a-newsfragment").evidence | any(test("docs-only"))' "$STORE" >/dev/null || { echo "FAIL reason must append to evidence"; exit 1; }
[ "$(jq -r 'select(.id=="a-newsfragment").last_confirmed' "$STORE")" = "2026-07-05T00:00:00Z" ] || { echo "FAIL last_confirmed must refresh"; exit 1; }
# the OTHER card is untouched
[ "$(jq -r 'select(.id=="a-tests-location").status' "$STORE")" = "active" ] || { echo "FAIL sibling card must be untouched"; exit 1; }
[ "$(jq -r 'select(.id=="a-tests-location").confidence' "$STORE")" = "0.8" ] || { echo "FAIL sibling confidence must be untouched"; exit 1; }
# store stays one-card-per-line valid JSON
[ "$(wc -l < "$STORE" | tr -d ' ')" = "2" ] || { echo "FAIL store must keep 2 lines"; exit 1; }
while IFS= read -r l || [ -n "$l" ]; do printf '%s' "$l" | jq -e . >/dev/null || { echo "FAIL every line must stay valid JSON"; exit 1; }; done < "$STORE"

# --- revive it (demoted -> active) ---
bash "$SS" --store "$STORE" --card-id a-newsfragment --status active --now 2026-07-05T01:00:00Z
[ "$(jq -r 'select(.id=="a-newsfragment").status' "$STORE")" = "active" ] || { echo "FAIL revive should set status=active"; exit 1; }
# confidence NOT overridden this time -> unchanged from the demote (0.3)
[ "$(jq -r 'select(.id=="a-newsfragment").confidence' "$STORE")" = "0.3" ] || { echo "FAIL omitted --confidence must leave confidence unchanged"; exit 1; }

# --- card not found -> exit 1, store unchanged ---
before=$(cat "$STORE")
set +e; bash "$SS" --store "$STORE" --card-id does-not-exist --status demoted 2>/dev/null; rc=$?; set -e
[ "$rc" -eq 1 ] || { echo "FAIL missing card should exit 1, got $rc"; exit 1; }
[ "$(cat "$STORE")" = "$before" ] || { echo "FAIL store must be unchanged when card not found"; exit 1; }

# --- bad status -> exit 2 ---
set +e; bash "$SS" --store "$STORE" --card-id a-newsfragment --status bogus 2>/dev/null; rc=$?; set -e
[ "$rc" -eq 2 ] || { echo "FAIL bad status should exit 2, got $rc"; exit 1; }

# --- non-numeric / out-of-range confidence -> exit 2 ---
set +e; bash "$SS" --store "$STORE" --card-id a-newsfragment --status active --confidence abc 2>/dev/null; rc=$?; set -e
[ "$rc" -eq 2 ] || { echo "FAIL non-numeric confidence should exit 2, got $rc"; exit 1; }
set +e; bash "$SS" --store "$STORE" --card-id a-newsfragment --status active --confidence 2.0 2>/dev/null; rc=$?; set -e
[ "$rc" -eq 2 ] || { echo "FAIL out-of-range confidence should exit 2, got $rc"; exit 1; }

# --- missing store -> exit 1 ---
set +e; bash "$SS" --store "$tmpdir/nope.jsonl" --card-id a --status demoted 2>/dev/null; rc=$?; set -e
[ "$rc" -eq 1 ] || { echo "FAIL missing store should exit 1, got $rc"; exit 1; }

# --- malformed store line -> exit 1 ---
badstore="$tmpdir/bad.jsonl"; printf '{not json}\n' > "$badstore"
set +e; bash "$SS" --store "$badstore" --card-id a --status demoted 2>/dev/null; rc=$?; set -e
[ "$rc" -eq 1 ] || { echo "FAIL malformed store line should exit 1, got $rc"; exit 1; }

# --- final line with no trailing newline is still processed (bash 3.2 last-line) ---
nlstore="$tmpdir/nonl.jsonl"
printf '%s' '{"id":"z1","scope":"repo","match":{"repo":"a/b"},"kind":"semantic","rule":"x","source":"scan","status":"active"}' > "$nlstore"
bash "$SS" --store "$nlstore" --card-id z1 --status demoted --now 2026-07-05T00:00:00Z
[ "$(jq -r '.status' "$nlstore")" = "demoted" ] || { echo "FAIL unterminated final line must be processed"; exit 1; }

echo "OK test_set_lesson_status.sh"
