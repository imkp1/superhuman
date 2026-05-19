# tests/scripts/test_catalog_generated.sh
#!/usr/bin/env bash
set -euo pipefail
export CLAUDE_PLUGIN_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

out=$(bash "$CLAUDE_PLUGIN_ROOT/scripts/profiler/catalog_generated.sh" \
        "$CLAUDE_PLUGIN_ROOT/tests/fixtures/generated_repo")

count=$(echo "$out" | jq '.entries | length')
[ "$count" = "2" ] || { echo "FAIL count: got $count want 2"; exit 1; }
echo "$out" | jq -e '.entries[] | select(.path | contains("_pb2.py"))' >/dev/null \
  || { echo "FAIL pb2 missing"; exit 1; }
echo "$out" | jq -e '.entries[] | select(.path | contains("v1.yaml"))' >/dev/null \
  || { echo "FAIL openapi missing"; exit 1; }

echo "OK test_catalog_generated.sh"
