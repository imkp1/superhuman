#!/usr/bin/env bash
set -euo pipefail
export CLAUDE_PLUGIN_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
source "$CLAUDE_PLUGIN_ROOT/scripts/lib/state.sh"
SS="$CLAUDE_PLUGIN_ROOT/scripts/profiler/scan_structure.sh"
SCHEMA="$CLAUDE_PLUGIN_ROOT/schemas/repo_scan.schema.json"
tmpdir=$(mktemp -d)

# --- build a fixture repo worktree ---
WT="$tmpdir/repo"
mkdir -p "$WT/src/auth" "$WT/tests" "$WT/docs" "$WT/.git/hooks"
printf 'def parse_jwt(token):\n    return token\ndef _verify(sig):\n    return True\n' > "$WT/src/auth/jwt.py"
echo 'def helper(): pass' > "$WT/src/util.py"
echo 'export function doThing() {}' > "$WT/src/client.js"
echo 'def test_parse(): pass' > "$WT/tests/test_jwt.py"
echo 'ignored = 1' > "$WT/.git/hooks/x.py"
echo '# docs' > "$WT/docs/readme.md"

out=$(bash "$SS" --repo apache/airflow --worktree "$WT" --head-sha deadbeef --now 2026-07-04T00:00:00Z)
echo "$out" > "$tmpdir/scan.json"

# validates against the repo_scan schema
validate_json "$SCHEMA" "$tmpdir/scan.json" || { echo "FAIL scan output must validate against repo_scan.schema.json"; exit 1; }

# required fields carried through from args
[ "$(printf '%s' "$out" | jq -r .repo)" = "apache/airflow" ] || { echo "FAIL repo"; exit 1; }
[ "$(printf '%s' "$out" | jq -r .head_sha)" = "deadbeef" ] || { echo "FAIL head_sha"; exit 1; }
[ "$(printf '%s' "$out" | jq -r .generated_at)" = "2026-07-04T00:00:00Z" ] || { echo "FAIL generated_at"; exit 1; }

# structural facts
[ "$(printf '%s' "$out" | jq -rc '.source_dirs')" = '["src"]' ] || { echo "FAIL source_dirs should be [src], got $(printf '%s' "$out" | jq -rc '.source_dirs')"; exit 1; }
[ "$(printf '%s' "$out" | jq -rc '.test_dirs')" = '["tests"]' ] || { echo "FAIL test_dirs should be [tests]"; exit 1; }
printf '%s' "$out" | jq -e '.languages | index("py")' >/dev/null || { echo "FAIL languages should include py"; exit 1; }
printf '%s' "$out" | jq -e '.languages | index("js")' >/dev/null || { echo "FAIL languages should include js"; exit 1; }
printf '%s' "$out" | jq -e '[.top_symbols[].name] | index("parse_jwt")' >/dev/null || { echo "FAIL top_symbols should include parse_jwt"; exit 1; }
# .git content is excluded
printf '%s' "$out" | jq -e '[.top_symbols[].file] | any(test("\\.git/"))' >/dev/null && { echo "FAIL .git content must be excluded"; exit 1; }

# --- missing/invalid worktree -> exit 2 ---
set +e
bash "$SS" --repo a/b --worktree "$tmpdir/nope" 2>/dev/null; rc=$?
set -e
[ "$rc" -eq 2 ] || { echo "FAIL missing worktree should exit 2, got $rc"; exit 1; }

echo "OK test_scan_structure.sh"
