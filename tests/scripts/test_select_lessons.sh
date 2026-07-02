#!/usr/bin/env bash
set -euo pipefail
export CLAUDE_PLUGIN_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SEL="$CLAUDE_PLUGIN_ROOT/scripts/lessons/select_lessons.sh"
tmpdir=$(mktemp -d)

repo_store="$tmpdir/lessons.jsonl"
global_store="$tmpdir/lessons_global.jsonl"

# repo card for THIS repo, enforced deterministic
cat >> "$repo_store" <<'EOF'
{"id":"news","scope":"repo","match":{"repo":"apache/airflow","lang":"python","paths":["airflow-core/**"]},"kind":"deterministic","rule":"newsfragment","check":{"id":"file_present","args":{"glob":"newsfragments/*"}},"source":"comment","evidence":[],"confidence":0.9,"hits":3,"repos_seen":["apache/airflow"],"status":"active","created":"2026-01-01T00:00:00Z","last_confirmed":"2026-06-01T00:00:00Z"}
EOF
# repo card for a DIFFERENT repo (must be excluded)
cat >> "$repo_store" <<'EOF'
{"id":"other","scope":"repo","match":{"repo":"other/repo","lang":"python"},"kind":"semantic","rule":"other repo rule","source":"comment","evidence":[],"confidence":0.9,"hits":1,"repos_seen":["other/repo"],"status":"active","created":"2026-01-01T00:00:00Z","last_confirmed":"2026-06-01T00:00:00Z"}
EOF
# retired repo card (must be excluded)
cat >> "$repo_store" <<'EOF'
{"id":"dead","scope":"repo","match":{"repo":"apache/airflow"},"kind":"semantic","rule":"retired rule","source":"comment","evidence":[],"confidence":0.9,"hits":1,"repos_seen":["apache/airflow"],"status":"retired","created":"2026-01-01T00:00:00Z","last_confirmed":"2026-01-01T00:00:00Z"}
EOF
# global semantic card, low confidence (advisory), python
cat >> "$global_store" <<'EOF'
{"id":"reuse-global","scope":"global","match":{"lang":"python"},"kind":"semantic","rule":"reuse existing util","source":"outcome","evidence":[],"confidence":0.6,"hits":2,"repos_seen":["a/b","c/d"],"status":"active","created":"2026-01-01T00:00:00Z","last_confirmed":"2026-06-01T00:00:00Z"}
EOF
# global card for a different language (must be excluded when lang=python)
cat >> "$global_store" <<'EOF'
{"id":"go-only","scope":"global","match":{"lang":"go"},"kind":"semantic","rule":"go rule","source":"outcome","evidence":[],"confidence":0.99,"hits":9,"repos_seen":["x/y","z/w"],"status":"active","created":"2026-01-01T00:00:00Z","last_confirmed":"2026-06-01T00:00:00Z"}
EOF

out=$(bash "$SEL" --repo apache/airflow --lang python --store "$repo_store" --store "$global_store")

ids=$(printf '%s' "$out" | jq -r '[.[].id] | join(",")')
# Expect exactly news + reuse-global, in that order (enforced deterministic first, then advisory).
[ "$ids" = "news,reuse-global" ] || { echo "FAIL expected 'news,reuse-global' got '$ids'"; exit 1; }

# lang filter excludes go-only; repo filter excludes other/repo; status excludes dead.
printf '%s' "$out" | jq -e 'any(.[]; .id=="go-only" or .id=="other" or .id=="dead")' >/dev/null && { echo "FAIL leaked an excluded card"; exit 1; }

# --- path-glob filter ---
echo "airflow-core/src/x.py" > "$tmpdir/changed.txt"
out2=$(bash "$SEL" --repo apache/airflow --lang python --changed-files "$tmpdir/changed.txt" --store "$repo_store" --store "$global_store")
printf '%s' "$out2" | jq -e 'any(.[]; .id=="news")' >/dev/null || { echo "FAIL news should match airflow-core path"; exit 1; }
echo "docs/readme.md" > "$tmpdir/changed2.txt"
out3=$(bash "$SEL" --repo apache/airflow --lang python --changed-files "$tmpdir/changed2.txt" --store "$repo_store" --store "$global_store")
printf '%s' "$out3" | jq -e 'any(.[]; .id=="news")' >/dev/null && { echo "FAIL news should NOT match docs/ path"; exit 1; }
# reuse-global has no match.paths -> still present regardless of changed files
printf '%s' "$out3" | jq -e 'any(.[]; .id=="reuse-global")' >/dev/null || { echo "FAIL pathless card should survive path filter"; exit 1; }

# --- cap ---
out4=$(bash "$SEL" --repo apache/airflow --lang python --cap 1 --store "$repo_store" --store "$global_store")
[ "$(printf '%s' "$out4" | jq 'length')" -eq 1 ] || { echo "FAIL cap 1 not honored"; exit 1; }
[ "$(printf '%s' "$out4" | jq -r '.[0].id')" = "news" ] || { echo "FAIL cap should keep top-ranked (news)"; exit 1; }

# --- no stores -> [] ---
out5=$(bash "$SEL" --repo apache/airflow --store "$tmpdir/nonexistent.jsonl")
[ "$out5" = "[]" ] || { echo "FAIL missing store should yield []"; exit 1; }

# --- dimension filter (regression guard: an unrequested dimension must be excluded) ---
dstore="$tmpdir/dims.jsonl"
cat > "$dstore" <<'EOF'
{"id":"proc","scope":"repo","match":{"repo":"apache/airflow","dimensions":["process"]},"kind":"semantic","rule":"p","source":"comment","evidence":[],"confidence":0.9,"hits":1,"repos_seen":["apache/airflow"],"status":"active","created":"2026-01-01T00:00:00Z","last_confirmed":"2026-06-01T00:00:00Z"}
{"id":"style","scope":"repo","match":{"repo":"apache/airflow","dimensions":["style"]},"kind":"semantic","rule":"s","source":"comment","evidence":[],"confidence":0.9,"hits":1,"repos_seen":["apache/airflow"],"status":"active","created":"2026-01-01T00:00:00Z","last_confirmed":"2026-06-01T00:00:00Z"}
EOF
outd=$(bash "$SEL" --repo apache/airflow --dimensions process --store "$dstore")
printf '%s' "$outd" | jq -e 'any(.[]; .id=="proc")'  >/dev/null || { echo "FAIL dimension filter should keep proc"; exit 1; }
printf '%s' "$outd" | jq -e 'any(.[]; .id=="style")' >/dev/null && { echo "FAIL dimension filter should drop style"; exit 1; }

echo "OK test_select_lessons.sh"
