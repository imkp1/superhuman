#!/usr/bin/env bash
set -euo pipefail
export CLAUDE_PLUGIN_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
source "$CLAUDE_PLUGIN_ROOT/scripts/lib/state.sh"
WRS="$CLAUDE_PLUGIN_ROOT/scripts/profiler/write_repo_scan.sh"
SCHEMA="$CLAUDE_PLUGIN_ROOT/schemas/repo_scan.schema.json"
tmpdir=$(mktemp -d); export HOME="$tmpdir"
WT="$tmpdir/repo"; mkdir -p "$WT/src"; echo 'def a(): pass' > "$WT/src/a.py"
out=$(bash "$WRS" --repo apache/airflow --worktree "$WT" --head-sha abc123 --now 2026-07-04T00:00:00Z)
dir=$(state_dir apache/airflow)
[ "$out" = "$dir/repo_scan.json" ] || { echo "FAIL should print published path, got $out"; exit 1; }
[ -f "$out" ] || { echo "FAIL published file missing"; exit 1; }
validate_json "$SCHEMA" "$out" || { echo "FAIL published scan must validate"; exit 1; }
[ "$(jq -r .head_sha "$out")" = "abc123" ] || { echo "FAIL head_sha"; exit 1; }
set +e; bash "$WRS" --repo a/b --worktree "$tmpdir/nope" 2>/dev/null; rc=$?; set -e
[ "$rc" -eq 2 ] || { echo "FAIL missing worktree exit 2, got $rc"; exit 1; }
echo "OK test_write_repo_scan.sh"
