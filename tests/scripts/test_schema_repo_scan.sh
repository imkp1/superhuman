#!/usr/bin/env bash
set -euo pipefail
export CLAUDE_PLUGIN_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
source "$CLAUDE_PLUGIN_ROOT/scripts/lib/state.sh"
SCHEMA="$CLAUDE_PLUGIN_ROOT/schemas/repo_scan.schema.json"
tmpdir=$(mktemp -d)
cat > "$tmpdir/ok.json" <<'EOF'
{
  "repo": "apache/airflow",
  "generated_at": "2026-07-03T00:00:00Z",
  "head_sha": "deadbeef",
  "default_branch": "main",
  "languages": ["python"],
  "source_dirs": ["airflow-core/src"],
  "test_dirs": ["tests"],
  "test_name_patterns": ["test_*.py"],
  "naming": {"functions": "snake"},
  "top_symbols": [{"name": "conf", "file": "airflow/configuration.py"}]
}
EOF
validate_json "$SCHEMA" "$tmpdir/ok.json" || { echo "FAIL valid repo_scan rejected"; exit 1; }
echo '{"repo":"a/b"}' > "$tmpdir/bad.json"
validate_json "$SCHEMA" "$tmpdir/bad.json" 2>/dev/null && { echo "FAIL repo_scan missing head_sha accepted"; exit 1; }
echo "OK test_schema_repo_scan.sh"
