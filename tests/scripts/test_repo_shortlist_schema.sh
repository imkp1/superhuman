#!/usr/bin/env bash
set -euo pipefail
CLAUDE_PLUGIN_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
export CLAUDE_PLUGIN_ROOT
source "$CLAUDE_PLUGIN_ROOT/scripts/lib/state.sh"
SCHEMA="$CLAUDE_PLUGIN_ROOT/schemas/repo_shortlist.schema.json"
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

cat > "$tmpdir/ok.json" <<'EOF'
{
  "generated_at": "2026-07-13T00:00:00Z",
  "criteria": {"min_stars": 20000, "min_score": 60},
  "repos": [
    {
      "rank": 1,
      "repo": "owner/repo",
      "stars": 45000,
      "category": "ai-ml",
      "language": "Python",
      "topics": ["machine-learning", "llm"],
      "description": "a repo",
      "scores": {"responsiveness": 9, "final": 87},
      "best_issue": {"number": 1234, "url": "https://github.com/owner/repo/issues/1234"},
      "notes": "tagged llm, responsive maintainers"
    }
  ]
}
EOF
validate_json "$SCHEMA" "$tmpdir/ok.json" || { echo "FAIL valid repo_shortlist rejected"; exit 1; }

echo '{"generated_at":"2026-07-13T00:00:00Z"}' > "$tmpdir/no_repos.json"
validate_json "$SCHEMA" "$tmpdir/no_repos.json" 2>/dev/null && {
  echo "FAIL repo_shortlist missing repos accepted"; exit 1; }

# validate_json degrades to a top-level required-key check when python jsonschema
# is absent, and repo/scores.final are nested inside repos[]. agents/repo-finder.md
# Step 5 asserts them with jq at write time. Keep this guard in lockstep with it.
row_guard() {  # row_guard <file> -> 0 if every row has repo + scores.final
  jq -e '.repos | length > 0 and all(.repo != null and .scores.final != null)' "$1" >/dev/null
}

row_guard "$tmpdir/ok.json" || { echo "FAIL row guard rejected a valid shortlist"; exit 1; }

# full_name -> repo mapping dropped on write.
cat > "$tmpdir/null_repo.json" <<'EOF'
{"generated_at":"2026-07-13T00:00:00Z","repos":[{"repo":null,"scores":{"final":87}}]}
EOF
row_guard "$tmpdir/null_repo.json" 2>/dev/null && { echo "FAIL null repo accepted"; exit 1; }

# Score written to a bare .score key instead of .scores.final.
cat > "$tmpdir/bare_score.json" <<'EOF'
{"generated_at":"2026-07-13T00:00:00Z","repos":[{"repo":"owner/repo","score":87,"scores":{}}]}
EOF
row_guard "$tmpdir/bare_score.json" 2>/dev/null && { echo "FAIL bare .score accepted"; exit 1; }

# commands/repo-finder.md must render scores.final, not score.
RENDERED=$(jq -r '.repos[] | "\(.scores.final)\t\(.repo)"' "$tmpdir/ok.json")
case "$RENDERED" in
  "87	owner/repo") ;;
  *) echo "FAIL render projection: got '$RENDERED'"; exit 1 ;;
esac
grep -q 'scores\.final' "$CLAUDE_PLUGIN_ROOT/commands/repo-finder.md" || {
  echo "FAIL commands/repo-finder.md does not render .scores.final"; exit 1; }

# Step 1 guards must exist in code, not only in prose. Each of these silently
# yields a partial candidate set that reads as a clean scan.
AGENT="$CLAUDE_PLUGIN_ROOT/agents/repo-finder.md"
grep -q 'FATAL: search failed for query' "$AGENT" || {
  echo "FAIL Step 1 does not abort on a failed search"; exit 1; }
grep -q 'any(.full_name == null)' "$AGENT" || {
  echo "FAIL Step 1 does not abort on null full_name"; exit 1; }
grep -q 'total_count' "$AGENT" || {
  echo "FAIL Step 1 does not retain total_count"; exit 1; }

# The query loop must not be fed by a pipe: a piped `while` runs in a subshell,
# where the aborts above terminate only the subshell and the scan continues.
grep -q 'DEFAULT_QUERIES" | while' "$AGENT" && {
  echo "FAIL Step 1 query loop is piped; aborts cannot exit the scan"; exit 1; }

# The per-candidate repo call this agent exists to avoid must stay deleted.
grep -q 'gh api repos/OWNER/REPO --jq' "$AGENT" && {
  echo "FAIL Step 2 re-fetches fields already carried by the Step 1 projection"; exit 1; }

echo "OK test_repo_shortlist_schema.sh"
