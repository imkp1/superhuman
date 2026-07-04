#!/usr/bin/env bash
set -euo pipefail
export CLAUDE_PLUGIN_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
source "$CLAUDE_PLUGIN_ROOT/scripts/lib/state.sh"
DF="$CLAUDE_PLUGIN_ROOT/scripts/profiler/dossier_fresh.sh"
tmpdir=$(mktemp -d); export HOME="$tmpdir"
dir=$(state_dir apache/airflow); mkdir -p "$dir"
atomic_write_json "$dir/dossier_meta.json" '{"repo":"apache/airflow","head_sha":"abc123","scanned_at":"2026-07-04T00:00:00Z","authored_at":"2026-07-04T00:01:00Z"}'
set +e; bash "$DF" --repo apache/airflow --head-sha abc123; rc=$?; set -e
[ "$rc" -eq 0 ] || { echo "FAIL matching head should be fresh (0), got $rc"; exit 1; }
set +e; bash "$DF" --repo apache/airflow --head-sha def456; rc=$?; set -e
[ "$rc" -eq 1 ] || { echo "FAIL moved head should be stale (1), got $rc"; exit 1; }
set +e; bash "$DF" --repo other/repo --head-sha abc123; rc=$?; set -e
[ "$rc" -eq 1 ] || { echo "FAIL no dossier_meta should be stale (1), got $rc"; exit 1; }
echo "OK test_dossier_fresh.sh"
