#!/usr/bin/env bash
set -euo pipefail
export CLAUDE_PLUGIN_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
source "$CLAUDE_PLUGIN_ROOT/scripts/lib/state.sh"

SCHEMA="$CLAUDE_PLUGIN_ROOT/schemas/run_telemetry.schema.json"
tmpdir=$(mktemp -d)

cat > "$tmpdir/ok.json" <<'EOF'
{"ts":"2026-05-01T12:00:00Z","iteration":1,"phase":"builder:initial","duration_s":142,"outcome":"ok","mode":"inline"}
EOF
validate_json "$SCHEMA" "$tmpdir/ok.json" || { echo "FAIL valid"; exit 1; }

echo '{}' > "$tmpdir/bad.json"
validate_json "$SCHEMA" "$tmpdir/bad.json" 2>/dev/null && { echo "FAIL bad accepted"; exit 1; }

echo "OK test_schema_run_telemetry.sh"
