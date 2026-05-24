# tests/scripts/test_delim.sh
#!/usr/bin/env bash
set -euo pipefail
export CLAUDE_PLUGIN_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
source "$CLAUDE_PLUGIN_ROOT/scripts/lib/delim.sh"

wrapped=$(wrap_external "hello world")
echo "$wrapped" | grep -q '<<<EXTERNAL_CONTENT id=' || { echo "FAIL wrap open"; exit 1; }
echo "$wrapped" | grep -q '<<<END id='              || { echo "FAIL wrap close"; exit 1; }
echo "$wrapped" | grep -q 'hello world'             || { echo "FAIL wrap body"; exit 1; }

open_id=$(echo "$wrapped" | sed -n 's/.*<<<EXTERNAL_CONTENT id=\([a-f0-9-]*\)>>>>.*/\1/p' | head -1)
close_id=$(echo "$wrapped" | sed -n 's/.*<<<END id=\([a-f0-9-]*\)>>>.*/\1/p' | head -1)
[ -n "$open_id" ] && [ "$open_id" = "$close_id" ] || { echo "FAIL uuid match"; exit 1; }

echo "OK test_delim.sh"
