#!/usr/bin/env bash
set -euo pipefail
export CLAUDE_PLUGIN_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
MC="$CLAUDE_PLUGIN_ROOT/scripts/lessons/merge_cards.sh"
tmpdir=$(mktemp -d)
NOW="2026-07-04T00:00:00Z"
store="$tmpdir/lessons.jsonl"; : > "$store"

detcard() { # $1=glob  -> a deterministic file_present card
  jq -nc --arg g "$1" '{id:("news-"+$g),scope:"repo",match:{repo:"apache/airflow"},kind:"deterministic",
    rule:"newsfragment",check:{id:"file_present",args:{glob:$g}},source:"comment",evidence:["PR#1"],
    confidence:0.5,hits:1,repos_seen:["apache/airflow"],status:"active",
    created:"2026-01-01T00:00:00Z",last_confirmed:"2026-01-01T00:00:00Z"}'
}

# --- new card is appended with birth defaults preserved from input ---
detcard "newsfragments/*" > "$tmpdir/c1.json"
bash "$MC" --store "$store" --card-file "$tmpdir/c1.json" --now "$NOW"
[ "$(jq -s length "$store")" -eq 1 ] || { echo "FAIL first insert should yield 1 card"; exit 1; }

# --- same key merges: hits 2, confidence 0.5+0.15=0.65, evidence unioned, last_confirmed refreshed ---
detcard "newsfragments/*" | jq -c '.evidence=["PR#2"] | .confidence=0.9' > "$tmpdir/c2.json"
bash "$MC" --store "$store" --card-file "$tmpdir/c2.json" --now "$NOW"
[ "$(jq -s length "$store")" -eq 1 ] || { echo "FAIL same key must not add a row"; exit 1; }
[ "$(jq -s '.[0].hits' "$store")" -eq 2 ] || { echo "FAIL hits should be 2"; exit 1; }
[ "$(jq -s '.[0].confidence' "$store")" = "0.65" ] || { echo "FAIL confidence should be 0.65 got $(jq -s '.[0].confidence' "$store")"; exit 1; }
[ "$(jq -sc '.[0].evidence' "$store")" = '["PR#1","PR#2"]' ] || { echo "FAIL evidence should union"; exit 1; }
[ "$(jq -s -r '.[0].last_confirmed' "$store")" = "$NOW" ] || { echo "FAIL last_confirmed should refresh to now"; exit 1; }

# --- different check.args VALUE => different key => NOT merged (Plan-1 review carry-forward) ---
detcard "docs/changelog/*" > "$tmpdir/c3.json"
bash "$MC" --store "$store" --card-file "$tmpdir/c3.json" --now "$NOW"
[ "$(jq -s length "$store")" -eq 2 ] || { echo "FAIL differing args value must be a distinct card"; exit 1; }

# --- retired card is revived on merge ---
echo '{"id":"z","scope":"repo","match":{"repo":"apache/airflow"},"kind":"semantic","rule":"reuse util","source":"comment","evidence":[],"confidence":0.3,"hits":1,"repos_seen":["apache/airflow"],"status":"retired","created":"2026-01-01T00:00:00Z","last_confirmed":"2026-01-01T00:00:00Z"}' > "$tmpdir/rev_store.jsonl"
echo '{"id":"z2","scope":"repo","match":{"repo":"apache/airflow"},"kind":"semantic","rule":"reuse util","source":"comment","evidence":[],"confidence":0.3,"hits":1,"repos_seen":["apache/airflow"],"status":"active","created":"2026-01-01T00:00:00Z","last_confirmed":"2026-01-01T00:00:00Z"}' > "$tmpdir/rev_card.json"
bash "$MC" --store "$tmpdir/rev_store.jsonl" --card-file "$tmpdir/rev_card.json" --now "$NOW"
[ "$(jq -s -r '.[0].status' "$tmpdir/rev_store.jsonl")" = "active" ] || { echo "FAIL retired card should revive to active"; exit 1; }

# --- regression: a store whose last line lacks a trailing newline must not lose that card ---
printf '%s' "$(detcard "keep/me/*")" > "$tmpdir/nonl.jsonl"   # NO trailing newline
detcard "other/key/*" > "$tmpdir/other.json"
bash "$MC" --store "$tmpdir/nonl.jsonl" --card-file "$tmpdir/other.json" --now "$NOW"
[ "$(jq -s length "$tmpdir/nonl.jsonl")" -eq 2 ] || { echo "FAIL unterminated last line was dropped on merge"; exit 1; }

# --- SAFETY: unknown check.id forces semantic and drops check ---
jq -nc '{id:"evil","scope":"repo","match":{"repo":"apache/airflow"},kind:"deterministic",rule:"x",check:{id:"run_shell",args:{cmd:"rm -rf /"}},source:"comment",evidence:[],confidence:0.5,hits:1,repos_seen:["apache/airflow"],status:"active",created:"2026-01-01T00:00:00Z",last_confirmed:"2026-01-01T00:00:00Z"}' > "$tmpdir/evil.json"
evstore="$tmpdir/evil_store.jsonl"; : > "$evstore"
bash "$MC" --store "$evstore" --card-file "$tmpdir/evil.json" --now "$NOW"
[ "$(jq -s -r '.[0].kind' "$evstore")" = "semantic" ] || { echo "FAIL unknown check.id must force semantic"; exit 1; }
[ "$(jq -s '.[0] | has("check")' "$evstore")" = "false" ] || { echo "FAIL forced-semantic card must drop check"; exit 1; }

echo "OK test_merge_cards.sh"
