#!/usr/bin/env bash
set -euo pipefail
export CLAUDE_PLUGIN_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

SCRIPT="$CLAUDE_PLUGIN_ROOT/scripts/builder/smoke_gate.sh"
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

SD="$tmpdir/state"
WD="$tmpdir/work"
OR="test/repo"
mkdir -p "$SD" "$WD"

# --- Test 1: pure-docs change skips python_import_root ---
# cmd=false so if the layer were run, exit would be non-zero.
cat > "$SD/smoke_registry.json" <<'EOF'
{"layers":[
  {"name":"python_import_root","cmd":"false","cwd":".","timeout_s":5},
  {"name":"node_require_root","cmd":"false","cwd":".","timeout_s":5}
]}
EOF

CHF="$tmpdir/changed_docs.txt"
printf 'README.md\ndocs/guide.md\n' > "$CHF"

set +e
bash "$SCRIPT" --state-dir "$SD" --changed-file "$CHF" --workdir "$WD" --owner-repo "$OR"
rc=$?
set -e
[ "$rc" -eq 0 ] || { echo "FAIL test1: pure-docs should skip all layers (rc=$rc)"; exit 1; }

# --- Test 2: python source change runs python_import_root (cmd=true, passes) ---
cat > "$SD/smoke_registry.json" <<'EOF'
{"layers":[
  {"name":"python_import_root","cmd":"true","cwd":".","timeout_s":5},
  {"name":"node_require_root","cmd":"true","cwd":".","timeout_s":5}
]}
EOF

CHF="$tmpdir/changed_py.txt"
printf 'src/app.py\nREADME.md\n' > "$CHF"

set +e
bash "$SCRIPT" --state-dir "$SD" --changed-file "$CHF" --workdir "$WD" --owner-repo "$OR"
rc=$?
set -e
[ "$rc" -eq 0 ] || { echo "FAIL test2: python source change with passing layer should exit 0 (rc=$rc)"; exit 1; }

# --- Test 3: failure of a layer → exit non-zero + mistake written ---
cat > "$SD/smoke_registry.json" <<'EOF'
{"layers":[
  {"name":"python_import_root","cmd":"false","cwd":".","timeout_s":5}
]}
EOF

CHF="$tmpdir/changed_py2.txt"
printf 'src/main.py\n' > "$CHF"
rm -f "$SD/mistakes.md"

set +e
bash "$SCRIPT" --state-dir "$SD" --changed-file "$CHF" --workdir "$WD" --owner-repo "$OR"
rc=$?
set -e
[ "$rc" -ne 0 ] || { echo "FAIL test3: failing layer should exit non-zero"; exit 1; }
[ -f "$SD/mistakes.md" ] || { echo "FAIL test3: mistakes.md not written"; exit 1; }
grep -q "builder:smoke_gate" "$SD/mistakes.md" || { echo "FAIL test3: mistakes.md missing tag"; exit 1; }

echo "OK test_smoke_gate.sh"
