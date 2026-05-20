# tests/scripts/test_prune_mistakes.sh
#!/usr/bin/env bash
set -euo pipefail
export CLAUDE_PLUGIN_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

tmpdir=$(mktemp -d)
SD="$tmpdir/state"
mkdir -p "$SD"
cat > "$SD/mistakes.md" <<'EOF'
## 2025-01-01T00:00:00Z tag=old repo=a/a
workdir: /x

old entry should be pruned

## 2026-05-15T00:00:00Z tag=new repo=a/a
workdir: /x

new entry should remain

EOF

bash "$CLAUDE_PLUGIN_ROOT/scripts/orchestrator/prune_mistakes.sh" \
  --file "$SD/mistakes.md" --max-age-days 30 --now 2026-05-18T00:00:00Z

grep -q "old entry should be pruned" "$SD/mistakes.md" && { echo "FAIL: old entry kept"; exit 1; }
grep -q "new entry should remain"   "$SD/mistakes.md" || { echo "FAIL: new entry lost"; exit 1; }
echo "OK test_prune_mistakes.sh"
