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

AGENT="$CLAUDE_PLUGIN_ROOT/agents/repo-finder.md"

# Step 1's guards are executed, not grepped: a literal-text assertion is satisfied
# by prose or a comment and proves nothing about behavior. Extract the Step 1
# block and run it against a stubbed gh. No network.
STEP1=$(awk '
  /^```bash$/ {inb=1; buf=""; next}
  /^```$/     {if (inb && buf ~ /DEFAULT_QUERIES=/) {printf "%s", buf; exit} inb=0; buf=""; next}
  inb         {buf = buf $0 "\n"}
' "$AGENT")
[ -n "$STEP1" ] || { echo "FAIL could not extract the Step 1 query block"; exit 1; }
# Trailing newline is load-bearing: the block ends in a heredoc terminator, and
# command substitution strips it. Without it, anything appended below fuses onto
# the EOF line and the heredoc never closes.
printf '%s\n' "$STEP1" > "$tmpdir/step1.sh"
bash -n "$tmpdir/step1.sh" || { echo "FAIL Step 1 block is not valid bash"; exit 1; }

mkdir -p "$tmpdir/bin"
cat > "$tmpdir/bin/gh" <<'EOF'
#!/usr/bin/env bash
case "${GH_STUB_MODE:-ok}" in
  fail) echo "gh: HTTP 403 rate limit exceeded" >&2; exit 1 ;;
  null) echo '{"total_count":2,"items":[{"full_name":null,"language":"Go"}]}' ;;
  *)    echo '{"total_count":63,"items":[{"full_name":"owner/repo","language":"Go","topics":["cli"],"stargazers_count":1,"pushed_at":"2026-07-01T00:00:00Z","archived":false,"open_issues_count":3,"default_branch":"main","description":"d"}]}' ;;
esac
EOF
chmod +x "$tmpdir/bin/gh"

# Step 1 accumulates rows into $CANDIDATES without printing them, so append a dump
# to observe what the loop actually collected. An abort exits before reaching it.
{ cat "$tmpdir/step1.sh"; echo 'printf "%s" "$CANDIDATES"'; } > "$tmpdir/run.sh"

run_step1() {  # run_step1 <mode> -> Step 1's exit code; stdout/stderr in $tmpdir/out
  GH_STUB_MODE="$1" PATH="$tmpdir/bin:$PATH" \
    bash "$tmpdir/run.sh" > "$tmpdir/out" 2>&1
}

# A failed search must abort the scan. Contributing zero rows instead leaves a
# partial candidate set that reads as a clean run.
run_step1 fail && { echo "FAIL Step 1 did not abort on a failed search"; exit 1; }
grep -q 'FATAL' "$tmpdir/out" || { echo "FAIL failed search did not report FATAL"; exit 1; }

# Field-name drift against the API yields null, not an error.
run_step1 null && { echo "FAIL Step 1 did not abort on null full_name"; exit 1; }
grep -q 'FATAL' "$tmpdir/out" || { echo "FAIL null full_name did not report FATAL"; exit 1; }

# Happy path: the projected row must actually be collected. Asserting only on the
# matched-of-total line is satisfied by "0 of 63 matched", so a regression that
# drops every candidate would pass.
run_step1 ok || { echo "FAIL Step 1 aborted on a valid response"; exit 1; }
grep -q '"full_name":"owner/repo"' "$tmpdir/out" || {
  echo "FAIL Step 1 collected no candidate row"; cat "$tmpdir/out"; exit 1; }
grep -q '"default_branch":"main"' "$tmpdir/out" || {
  echo "FAIL Step 1 projection dropped default_branch (raw() breaks without it)"; exit 1; }
grep -q '1 of 63 matched' "$tmpdir/out" || {
  echo "FAIL Step 1 does not report matched-of-total"; cat "$tmpdir/out"; exit 1; }

# Both aborts above only terminate the scan if the loop runs in the current shell.
# A piped `while` runs in a subshell, where `exit` kills the subshell and the scan
# continues — the guards would pass review and do nothing. Checked on code with
# comments stripped, so a comment cannot satisfy or trip it.
STEP1_CODE=$(printf '%s' "$STEP1" | sed 's/#.*//')
printf '%s' "$STEP1_CODE" | grep -qE '\|[[:space:]]*while' && {
  echo "FAIL Step 1 query loop is piped; its aborts cannot exit the scan"; exit 1; }
printf '%s' "$STEP1_CODE" | grep -q 'done <<' || {
  echo "FAIL Step 1 query loop is not heredoc-fed"; exit 1; }

# The per-candidate repo call must stay deleted. Match the ROOT repos/OWNER/REPO
# endpoint, not the field names: `gh api "repos/$name"` returns all four projected
# fields whether or not a field name appears on that line, and a line-continued
# command hides the field list from a line-oriented grep entirely.
#
# Subresources are legitimate and must keep working: /git/trees, /contributors,
# /issues/comments, /pulls carry data no search result holds. Banning `gh api
# repos/` wholesale, as review proposed, would break all four.
#
# Normalize first: strip comments, join line continuations, collapse whitespace.
NORM=$(sed 's/#.*//' "$AGENT" \
  | sed -e :a -e '/\\$/{N; s/\\\n//; ta' -e '}' \
  | tr -s '[:space:]' ' ')
#
# Allowlist the subresources rather than pattern-matching the root form: the owner
# and repo may be a variable (`gh api "repos/$full_name"`), which carries no
# literal owner/repo slash to match on. Anything without a subresource is a root
# fetch, however it is spelled.
REFETCH=$(printf '%s\n' "$NORM" \
  | grep -oE "gh api [^|;]*repos/[^\"' )]*" \
  | grep -oE "repos/[^\"' )]*" \
  | grep -vE "/(git/trees|contributors|issues|pulls|commits|compare|releases|contents|labels)" \
  || true)
[ -z "$REFETCH" ] || {
  echo "FAIL Step 2 re-fetches the root repos endpoint ($REFETCH); Step 1 already carries those fields"
  exit 1; }

echo "OK test_repo_shortlist_schema.sh"
