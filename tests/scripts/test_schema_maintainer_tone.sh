#!/usr/bin/env bash
set -euo pipefail
export CLAUDE_PLUGIN_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
source "$CLAUDE_PLUGIN_ROOT/scripts/lib/state.sh"

SCHEMA="$CLAUDE_PLUGIN_ROOT/schemas/maintainer_tone.schema.json"
tmpdir=$(mktemp -d)

cat > "$tmpdir/ok.json" <<'EOF'
{
  "repo": "apache/airflow",
  "generated_at": "2026-05-01T12:00:00Z",
  "maintainers": {
    "vincbeck": {
      "prefers": "short_replies",
      "signals": ["brief acknowledgements", "avoids emoji", "quotes code"],
      "last_updated": "2026-05-01T12:00:00Z"
    },
    "uranusjr": {
      "prefers": "detailed_rationale",
      "signals": ["asks 'why not X'", "expects tradeoff discussion"],
      "last_updated": "2026-04-27T09:00:00Z"
    }
  }
}
EOF
validate_json "$SCHEMA" "$tmpdir/ok.json" || { echo "FAIL valid"; exit 1; }

echo '{}' > "$tmpdir/bad.json"
validate_json "$SCHEMA" "$tmpdir/bad.json" 2>/dev/null && { echo "FAIL bad accepted"; exit 1; }

echo "OK test_schema_maintainer_tone.sh"
