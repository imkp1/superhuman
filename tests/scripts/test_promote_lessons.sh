#!/usr/bin/env bash
set -euo pipefail
export CLAUDE_PLUGIN_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PL="$CLAUDE_PLUGIN_ROOT/scripts/lessons/promote_lessons.sh"
tmpdir=$(mktemp -d)
NOW="2026-07-04T00:00:00Z"

# same semantic rule ("reuse the util") in each repo store -> same card_key
repocard() { jq -nc --arg id "$1" --arg repo "$2" '{id:$id,scope:"repo",match:{repo:$repo},kind:"semantic",rule:"reuse the util",source:"comment",evidence:[],confidence:0.8,hits:1,repos_seen:[$repo],status:"active",created:"2026-01-01T00:00:00Z",last_confirmed:"2026-01-01T00:00:00Z"}'; }
repocard idA a/one   > "$tmpdir/rA.jsonl"
repocard idB b/two   > "$tmpdir/rB.jsonl"
repocard idC c/three > "$tmpdir/rC.jsonl"
glob="$tmpdir/lessons_global.jsonl"; : > "$glob"

# --- 2 distinct repos -> one global-candidate (advisory), repos_seen unioned ---
bash "$PL" --repo-store "$tmpdir/rA.jsonl" --repo-store "$tmpdir/rB.jsonl" --global-store "$glob" --now "$NOW"
[ "$(jq -s length "$glob")" -eq 1 ] || { echo "FAIL 2 repos should yield 1 global row"; exit 1; }
[ "$(jq -s -r '.[0].scope' "$glob")" = "global-candidate" ] || { echo "FAIL 2 repos should be global-candidate got $(jq -s -r '.[0].scope' "$glob")"; exit 1; }
[ "$(jq -s -rc '.[0].repos_seen | sort | join(",")' "$glob")" = "a/one,b/two" ] || { echo "FAIL candidate repos_seen"; exit 1; }

# --- 3rd distinct repo -> graduate to global (enforced), still one row ---
bash "$PL" --repo-store "$tmpdir/rA.jsonl" --repo-store "$tmpdir/rB.jsonl" --repo-store "$tmpdir/rC.jsonl" --global-store "$glob" --now "$NOW"
[ "$(jq -s length "$glob")" -eq 1 ] || { echo "FAIL graduation must upsert, not add a row"; exit 1; }
[ "$(jq -s -r '.[0].scope' "$glob")" = "global" ] || { echo "FAIL 3 repos should graduate to global"; exit 1; }
[ "$(jq -s -rc '.[0].repos_seen | sort | join(",")' "$glob")" = "a/one,b/two,c/three" ] || { echo "FAIL global repos_seen"; exit 1; }

# --- a below-threshold round (1 repo) must NOT downgrade or drop the existing global ---
bash "$PL" --repo-store "$tmpdir/rA.jsonl" --global-store "$glob" --now "$NOW"
[ "$(jq -s length "$glob")" -eq 1 ] || { echo "FAIL existing global dropped on below-threshold round"; exit 1; }
[ "$(jq -s -r '.[0].scope' "$glob")" = "global" ] || { echo "FAIL existing global downgraded"; exit 1; }

# --- a rule in only ONE repo never promotes ---
glob2="$tmpdir/g2.jsonl"; : > "$glob2"
bash "$PL" --repo-store "$tmpdir/rA.jsonl" --global-store "$glob2" --now "$NOW"
[ "$(jq -s length "$glob2")" -eq 0 ] || { echo "FAIL single-repo rule must not promote"; exit 1; }

echo "OK test_promote_lessons.sh"
