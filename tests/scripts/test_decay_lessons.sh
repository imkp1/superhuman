#!/usr/bin/env bash
set -euo pipefail
export CLAUDE_PLUGIN_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
DL="$CLAUDE_PLUGIN_ROOT/scripts/lessons/decay_lessons.sh"
tmpdir=$(mktemp -d)
NOW="2026-07-04T00:00:00Z"
store="$tmpdir/lessons.jsonl"

card() { # $1=id $2=confidence $3=last_confirmed $4=status
  jq -nc --arg id "$1" --argjson c "$2" --arg lc "$3" --arg st "$4" \
    '{id:$id,scope:"repo",match:{repo:"x/y"},kind:"semantic",rule:("r-"+$id),source:"comment",
      evidence:[],confidence:$c,hits:1,repos_seen:["x/y"],status:$st,created:"2025-01-01T00:00:00Z",last_confirmed:$lc}'
}
{
  card fresh   0.9  "2026-07-01T00:00:00Z" active   # age 3 days  -> untouched
  card decayed 0.5  "2026-01-01T00:00:00Z" active   # age ~184>180 -> 0.5-0.1=0.4, stays active
  card lowconf 0.30 "2026-01-01T00:00:00Z" active   # age ~184>180 -> 0.30-0.1=0.20<0.25 -> retired
  card ancient 0.9  "2025-01-01T00:00:00Z" active   # age ~549>360 -> retired (by age)
  jq -nc '{id:"nolc",scope:"repo",match:{repo:"x/y"},kind:"semantic",rule:"r-nolc",source:"comment",evidence:[],confidence:0.9,hits:1,repos_seen:["x/y"],status:"active",created:"2025-01-01T00:00:00Z"}'  # no last_confirmed -> untouched
} > "$store"

bash "$DL" --store "$store" --now "$NOW"

get() { jq -s -r --arg id "$1" --arg f "$2" '.[] | select(.id==$id) | .[$f] | tostring' "$store"; }
[ "$(get fresh confidence)" = "0.9" ] && [ "$(get fresh status)" = "active" ] || { echo "FAIL fresh card must be untouched"; exit 1; }
[ "$(get decayed confidence)" = "0.4" ] && [ "$(get decayed status)" = "active" ] || { echo "FAIL decayed card should be 0.4/active got $(get decayed confidence)/$(get decayed status)"; exit 1; }
[ "$(get lowconf status)" = "retired" ] || { echo "FAIL lowconf card should retire (conf<retire-max)"; exit 1; }
[ "$(get ancient status)" = "retired" ] || { echo "FAIL ancient card should retire (age>2*decay-days)"; exit 1; }
[ "$(get nolc confidence)" = "0.9" ] && [ "$(get nolc status)" = "active" ] || { echo "FAIL card without last_confirmed must be untouched"; exit 1; }

# --- malformed store line -> decay aborts (nonzero), store unchanged, no temp leak ---
printf 'not json at all\n' > "$tmpdir/corrupt.jsonl"
before=$(cat "$tmpdir/corrupt.jsonl")
set +e
bash "$DL" --store "$tmpdir/corrupt.jsonl" --now "$NOW" 2>/dev/null
rc=$?
set -e
[ "$rc" -ne 0 ] || { echo "FAIL decay should abort on malformed line"; exit 1; }
[ "$(cat "$tmpdir/corrupt.jsonl")" = "$before" ] || { echo "FAIL decay must not mutate store on abort"; exit 1; }
[ -z "$(ls "$tmpdir"/corrupt.jsonl.tmp.* 2>/dev/null)" ] || { echo "FAIL decay leaked a temp file on abort"; exit 1; }

echo "OK test_decay_lessons.sh"
