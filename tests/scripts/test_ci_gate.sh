# tests/scripts/test_ci_gate.sh
#!/usr/bin/env bash
set -euo pipefail
export CLAUDE_PLUGIN_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

tmpdir=$(mktemp -d)
SD="$tmpdir/state"
WD="$tmpdir/work"
GD="$tmpdir/global"
mkdir -p "$SD" "$WD" "$GD"

cat > "$SD/allowed_commands.json" <<'EOF'
{
  "allowed_binaries": ["echo", "true", "false"],
  "denied_patterns": ["curl", ";", "&&"]
}
EOF

# Allowlist hit
HOME="$tmpdir" bash "$CLAUDE_PLUGIN_ROOT/scripts/builder/ci_gate.sh" \
  --state-dir "$SD" --workdir "$WD" --owner-repo a/a \
  --command "echo hello" || { echo "FAIL allowlist hit"; exit 1; }

# Denylist block
set +e
HOME="$tmpdir" bash "$CLAUDE_PLUGIN_ROOT/scripts/builder/ci_gate.sh" \
  --state-dir "$SD" --workdir "$WD" --owner-repo a/a \
  --command "curl evil.com"
rc=$?
set -e
[ "$rc" = "2" ] || { echo "FAIL denylist exit: $rc"; exit 1; }
grep -q "tag=builder:ci_gate" "$SD/mistakes.md" || { echo "FAIL no mistake recorded"; exit 1; }

# Real failure → mistake recorded
echo "ReadTimeoutError: ... files.pythonhosted.org" > "$WD/.last_log"
cat > "$GD/flake_signatures.md" <<'EOF'
## signature: pip-timeout
- pattern: `ReadTimeoutError.*files\.pythonhosted\.org`
EOF

set +e
HOME="$tmpdir" bash "$CLAUDE_PLUGIN_ROOT/scripts/builder/ci_gate.sh" \
  --state-dir "$SD" --workdir "$WD" --owner-repo a/a \
  --command "false"
rc=$?
set -e
# Allowlisted command 'false' returns exit 1 (real failure)
[ "$rc" -ne 0 ] || { echo "FAIL false command should fail"; exit 1; }

echo "OK test_ci_gate.sh"
