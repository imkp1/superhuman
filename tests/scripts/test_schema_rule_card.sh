#!/usr/bin/env bash
set -euo pipefail
export CLAUDE_PLUGIN_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
source "$CLAUDE_PLUGIN_ROOT/scripts/lib/state.sh"
SCHEMA="$CLAUDE_PLUGIN_ROOT/schemas/rule_card.schema.json"
tmpdir=$(mktemp -d)

# A well-formed deterministic repo card validates.
cat > "$tmpdir/ok.json" <<'EOF'
{
  "id": "apache-airflow-newsfragment",
  "scope": "repo",
  "match": {"repo": "apache/airflow", "lang": "python", "paths": ["airflow-core/**"], "dimensions": ["process"]},
  "kind": "deterministic",
  "rule": "Add a newsfragment under newsfragments/ for any user-facing change.",
  "check": {"id": "file_present", "args": {"glob": "newsfragments/*"}},
  "source": "comment",
  "evidence": ["PR#65685 review by vincbeck 2026-04-23"],
  "confidence": 0.8,
  "hits": 3,
  "repos_seen": ["apache/airflow"],
  "status": "active",
  "created": "2026-04-23T10:00:00Z",
  "last_confirmed": "2026-06-30T10:00:00Z"
}
EOF
validate_json "$SCHEMA" "$tmpdir/ok.json" || { echo "FAIL valid card rejected"; exit 1; }

# A well-formed semantic global card (no check) validates.
cat > "$tmpdir/ok2.json" <<'EOF'
{
  "id": "reuse-existing-util-global",
  "scope": "global",
  "match": {"lang": "python", "dimensions": ["correctness"]},
  "kind": "semantic",
  "rule": "Reuse an existing utility instead of adding a near-duplicate.",
  "source": "outcome",
  "evidence": [],
  "confidence": 0.9,
  "hits": 5,
  "repos_seen": ["a/b", "c/d", "e/f"],
  "status": "active",
  "created": "2026-05-01T00:00:00Z",
  "last_confirmed": "2026-06-01T00:00:00Z"
}
EOF
validate_json "$SCHEMA" "$tmpdir/ok2.json" || { echo "FAIL valid semantic card rejected"; exit 1; }

# Missing a required field (rule) fails.
echo '{"id":"x","scope":"repo","match":{},"kind":"semantic","source":"comment","confidence":0.5,"hits":1,"repos_seen":[],"status":"active","created":"2026-01-01T00:00:00Z","last_confirmed":"2026-01-01T00:00:00Z"}' > "$tmpdir/bad.json"
validate_json "$SCHEMA" "$tmpdir/bad.json" 2>/dev/null && { echo "FAIL card missing 'rule' accepted"; exit 1; }

echo "OK test_schema_rule_card.sh"
