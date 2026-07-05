#!/usr/bin/env bash
set -euo pipefail
export CLAUDE_PLUGIN_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
source "$CLAUDE_PLUGIN_ROOT/scripts/lib/state.sh"
SCHEMA="$CLAUDE_PLUGIN_ROOT/schemas/dossier_meta.schema.json"
tmpdir=$(mktemp -d)
cat > "$tmpdir/ok.json" <<'EOF'
{"repo":"apache/airflow","head_sha":"deadbeef","scanned_at":"2026-07-03T00:00:00Z","authored_at":"2026-07-03T00:05:00Z","scan_digest":"sha256:abc"}
EOF
validate_json "$SCHEMA" "$tmpdir/ok.json" || { echo "FAIL valid dossier_meta rejected"; exit 1; }
echo '{"repo":"a/b","head_sha":"x"}' > "$tmpdir/bad.json"
validate_json "$SCHEMA" "$tmpdir/bad.json" 2>/dev/null && { echo "FAIL dossier_meta missing timestamps accepted"; exit 1; }
echo "OK test_schema_dossier_meta.sh"
