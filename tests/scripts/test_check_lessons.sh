#!/usr/bin/env bash
set -euo pipefail
export CLAUDE_PLUGIN_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CHK="$CLAUDE_PLUGIN_ROOT/scripts/lessons/check_lessons.sh"
tmpdir=$(mktemp -d)

# Context: worktree WITHOUT a newsfragment, subject is non-conventional.
mkdir -p "$tmpdir/wt/src"
echo x > "$tmpdir/wt/src/a.py"
cat > "$tmpdir/ctx.json" <<EOF
{"worktree":"$tmpdir/wt","changed_files":["src/a.py"],"head_subject":"did stuff","new_identifiers":[]}
EOF

# Enforced deterministic card: newsfragment required -> VIOLATED (none present).
cat > "$tmpdir/cards.json" <<'EOF'
[
 {"id":"news","scope":"repo","match":{"repo":"apache/airflow"},"kind":"deterministic","rule":"newsfragment required","check":{"id":"file_present","args":{"glob":"newsfragments/*"}},"source":"comment","evidence":[],"confidence":0.9,"hits":3,"repos_seen":["apache/airflow"],"status":"active","created":"2026-01-01T00:00:00Z","last_confirmed":"2026-06-01T00:00:00Z"},
 {"id":"cand","scope":"global-candidate","match":{},"kind":"deterministic","rule":"conventional commits","check":{"id":"commit_matches","args":{"convention":"conventional"}},"source":"outcome","evidence":[],"confidence":0.9,"hits":2,"repos_seen":["a/b","c/d"],"status":"active","created":"2026-01-01T00:00:00Z","last_confirmed":"2026-06-01T00:00:00Z"},
 {"id":"sem","scope":"repo","match":{"repo":"apache/airflow"},"kind":"semantic","rule":"reuse existing util","source":"comment","evidence":[],"confidence":0.9,"hits":1,"repos_seen":["apache/airflow"],"status":"active","created":"2026-01-01T00:00:00Z","last_confirmed":"2026-06-01T00:00:00Z"}
]
EOF

set +e
out=$(bash "$CHK" --cards "$tmpdir/cards.json" --context "$tmpdir/ctx.json"); rc=$?
set -e
[ "$rc" -eq 1 ] || { echo "FAIL expected exit 1 on enforced violation, got $rc"; exit 1; }
# 'news' is an enforced violation; 'cand' is a candidate violation (advisory); 'sem' is skipped.
printf '%s' "$out" | jq -e '.violations | any(.id=="news")'  >/dev/null || { echo "FAIL news should be a violation"; exit 1; }
printf '%s' "$out" | jq -e '.advisories | any(.id=="cand")'  >/dev/null || { echo "FAIL cand should be an advisory"; exit 1; }
printf '%s' "$out" | jq -e '.violations | any(.id=="cand")'  >/dev/null && { echo "FAIL candidate must not be an enforced violation"; exit 1; }
[ "$(printf '%s' "$out" | jq '.checked')" -eq 2 ] || { echo "FAIL should have checked 2 deterministic cards"; exit 1; }

# Now satisfy the newsfragment rule -> no enforced violation -> exit 0.
mkdir -p "$tmpdir/wt/newsfragments"
echo x > "$tmpdir/wt/newsfragments/1.bugfix"
set +e
out2=$(bash "$CHK" --cards "$tmpdir/cards.json" --context "$tmpdir/ctx.json"); rc2=$?
set -e
[ "$rc2" -eq 0 ] || { echo "FAIL expected exit 0 once newsfragment present, got $rc2"; exit 1; }
printf '%s' "$out2" | jq -e '.violations | length == 0' >/dev/null || { echo "FAIL violations should be empty"; exit 1; }

# Empty/absent cards -> pass (graceful degradation).
set +e
out3=$(bash "$CHK" --cards "$tmpdir/none.json" --context "$tmpdir/ctx.json"); rc3=$?
set -e
[ "$rc3" -eq 0 ] || { echo "FAIL missing cards file should exit 0"; exit 1; }
[ "$(printf '%s' "$out3" | jq '.checked')" -eq 0 ] || { echo "FAIL checked should be 0"; exit 1; }

echo "OK test_check_lessons.sh"
