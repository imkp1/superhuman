#!/usr/bin/env bash
# tests/scripts/test_usage_event.sh
set -uo pipefail
export CLAUDE_PLUGIN_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT="$CLAUDE_PLUGIN_ROOT/scripts/lib/usage_event.sh"
CURVER=$(jq -r '.version // "unknown"' "$CLAUDE_PLUGIN_ROOT/.claude-plugin/plugin.json")

fail() { echo "FAIL: $1"; exit 1; }

setup() {
  TMP=$(mktemp -d)
  export HOME="$TMP/home"
  mkdir -p "$HOME/.superhuman/global"
  BIN="$TMP/bin"; mkdir -p "$BIN"
  export CURL_LOG="$TMP/curl.log"; : > "$CURL_LOG"
  cat > "$BIN/curl" <<'EOF'
#!/usr/bin/env bash
echo "$@" >> "$CURL_LOG"
EOF
  cat > "$BIN/gh" <<'EOF'
#!/usr/bin/env bash
[ -n "${GH_FAIL:-}" ] && exit 1
echo "octocat"
EOF
  chmod +x "$BIN/curl" "$BIN/gh"
  export PATH="$BIN:$PATH"
  unset SUPERHUMAN_TELEMETRY GH_FAIL
}
teardown() { rm -rf "$TMP"; }

enable() { printf '{"enabled":true}\n' > "$HOME/.superhuman/global/telemetry.json"; }
ident()  { printf '{"github_username":"octocat"}\n' > "$HOME/.superhuman/global/identity.json"; }
lastver(){ printf '{"version":"%s"}\n' "$1" > "$HOME/.superhuman/global/last_version.json"; }

# 1. env opt-out -> no send
setup
SUPERHUMAN_TELEMETRY=off bash "$SCRIPT" --command contribute
[ -s "$CURL_LOG" ] && fail "env off should not send"
teardown

# 2. flag opt-out -> no send
setup
printf '{"enabled":false}\n' > "$HOME/.superhuman/global/telemetry.json"
bash "$SCRIPT" --command contribute
[ -s "$CURL_LOG" ] && fail "flag disabled should not send"
teardown

# 3. used event carries command + version
setup; enable; ident
bash "$SCRIPT" --command repo-finder
grep -q 'superhuman_used'         "$CURL_LOG" || fail "missing used event"
grep -q '"command":"repo-finder"' "$CURL_LOG" || fail "missing command prop"
grep -q "\"version\":\"$CURVER\"" "$CURL_LOG" || fail "missing version prop"
teardown

# 4. lifecycle install: no last_version.json -> kind install, cache written
setup; enable; ident
bash "$SCRIPT" --command contribute
grep -q 'superhuman_lifecycle'   "$CURL_LOG" || fail "install: missing lifecycle event"
grep -q '"kind":"install"'       "$CURL_LOG" || fail "install: wrong kind"
grep -q '"prev_version":""'      "$CURL_LOG" || fail "install: prev_version should be empty"
[ -f "$HOME/.superhuman/global/last_version.json" ] || fail "install: cache not written"
grep -q "\"version\":\"$CURVER\"" "$HOME/.superhuman/global/last_version.json" || fail "install: cache wrong version"
teardown

# 5. lifecycle update: cached older version -> kind update, prev carried
setup; enable; ident; lastver "0.0.1"
bash "$SCRIPT" --command contribute
grep -q '"kind":"update"'         "$CURL_LOG" || fail "update: wrong kind"
grep -q '"prev_version":"0.0.1"'  "$CURL_LOG" || fail "update: missing prev_version"
grep -q "\"version\":\"$CURVER\"" "$HOME/.superhuman/global/last_version.json" || fail "update: cache not bumped"
teardown

# 6. lifecycle none: cached == current -> used sent, NO lifecycle
setup; enable; ident; lastver "$CURVER"
bash "$SCRIPT" --command contribute
grep -q 'superhuman_used'     "$CURL_LOG" || fail "none: used should still send"
grep -q 'superhuman_lifecycle' "$CURL_LOG" && fail "none: lifecycle should NOT send on same version"
teardown

# 7. print mode -> payload on stderr, no send
setup; enable; ident; lastver "$CURVER"
out=$(SUPERHUMAN_TELEMETRY=print bash "$SCRIPT" --command contribute 2>&1 >/dev/null)
echo "$out" | grep -q 'superhuman_used' || fail "print mode should emit used payload"
[ -s "$CURL_LOG" ] && fail "print mode should not send"
teardown

# 8. unknown-user fallback
setup; enable; export GH_FAIL=1
bash "$SCRIPT" --command contribute
grep -q 'unknown' "$CURL_LOG" || fail "should fall back to unknown distinct_id"
teardown

echo "OK test_usage_event.sh"
