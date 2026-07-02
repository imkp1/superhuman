#!/usr/bin/env bash
set -euo pipefail
export CLAUDE_PLUGIN_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
source "$CLAUDE_PLUGIN_ROOT/scripts/lib/lesson_checks.sh"
tmpdir=$(mktemp -d)

# --- is_known_check / known_checks ---
is_known_check file_present   || { echo "FAIL file_present should be known"; exit 1; }
is_known_check totally_made_up && { echo "FAIL made-up check should be unknown"; exit 1; }

# --- run_check: unknown id fail-opens (pass) ---
run_check made_up '{}' '{}' || { echo "FAIL unknown check should fail-open pass"; exit 1; }

# --- file_present ---
mkdir -p "$tmpdir/wt/newsfragments"
echo x > "$tmpdir/wt/newsfragments/123.bugfix"
ctx=$(jq -nc --arg wt "$tmpdir/wt" '{worktree:$wt,changed_files:[],head_subject:"",new_identifiers:[]}')
run_check file_present '{"glob":"newsfragments/*"}' "$ctx" || { echo "FAIL file_present should pass (file exists)"; exit 1; }
run_check file_present '{"glob":"CHANGELOG.md"}' "$ctx"    && { echo "FAIL file_present should violate (missing)"; exit 1; }
# no worktree -> fail-open pass
run_check file_present '{"glob":"whatever"}' '{"worktree":""}' || { echo "FAIL file_present should fail-open with no worktree"; exit 1; }

# --- file_in_dir (class=test) ---
ctx_ok=$(jq -nc '{changed_files:["tests/test_x.py","src/a.py"]}')
run_check file_in_dir '{"class":"test","path_glob":"tests/*"}' "$ctx_ok"  || { echo "FAIL file_in_dir should pass (test under tests/)"; exit 1; }
ctx_bad=$(jq -nc '{changed_files:["src/test_x.py"]}')
run_check file_in_dir '{"class":"test","path_glob":"tests/*"}' "$ctx_bad" && { echo "FAIL file_in_dir should violate (test outside tests/)"; exit 1; }
# no test-named files -> not applicable -> pass
ctx_none=$(jq -nc '{changed_files:["src/a.py"]}')
run_check file_in_dir '{"class":"test","path_glob":"tests/*"}' "$ctx_none" || { echo "FAIL file_in_dir should pass (no tests changed)"; exit 1; }

# --- commit_matches ---
run_check commit_matches '{"convention":"conventional"}' '{"head_subject":"fix: crash on empty input"}' || { echo "FAIL conventional should pass"; exit 1; }
run_check commit_matches '{"convention":"conventional"}' '{"head_subject":"random subject"}'            && { echo "FAIL conventional should violate"; exit 1; }
run_check commit_matches '{"convention":"freeform"}'     '{"head_subject":"anything at all"}'          || { echo "FAIL freeform should always pass"; exit 1; }
run_check commit_matches '{"convention":"conventional"}' '{"head_subject":""}'                          || { echo "FAIL empty subject should fail-open pass"; exit 1; }

# --- identifier_case ---
run_check identifier_case '{"style":"snake"}'  '{"new_identifiers":["do_thing","_helper"]}' || { echo "FAIL snake should pass"; exit 1; }
run_check identifier_case '{"style":"snake"}'  '{"new_identifiers":["doThing"]}'            && { echo "FAIL snake should violate camelCase"; exit 1; }
run_check identifier_case '{"style":"pascal"}' '{"new_identifiers":["MyClass"]}'            || { echo "FAIL pascal should pass"; exit 1; }
run_check identifier_case '{"style":"snake"}'  '{"new_identifiers":[]}'                     || { echo "FAIL no identifiers should pass"; exit 1; }

# --- card_key ---
d1=$(card_key '{"kind":"deterministic","check":{"id":"file_present","args":{"glob":"newsfragments/*"}},"rule":"a"}')
d2=$(card_key '{"kind":"deterministic","check":{"id":"file_present","args":{"glob":"newsfragments/*"}},"rule":"DIFFERENT text"}')
[ "$d1" = "$d2" ] || { echo "FAIL deterministic key should ignore rule text"; exit 1; }
s1=$(card_key '{"kind":"semantic","rule":"Reuse   the existing util."}')
s2=$(card_key '{"kind":"semantic","rule":"reuse the existing UTIL."}')
[ "$s1" = "$s2" ] || { echo "FAIL semantic key should normalize case/space: [$s1] vs [$s2]"; exit 1; }

echo "OK test_lesson_checks.sh"
