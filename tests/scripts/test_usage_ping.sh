#!/usr/bin/env bash
# tests/scripts/test_usage_ping.sh
set -uo pipefail
export CLAUDE_PLUGIN_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT="$CLAUDE_PLUGIN_ROOT/scripts/lib/usage_ping.sh"

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

enable() { printf '{"enabled":true}\n'  > "$HOME/.superhuman/global/telemetry.json"; }
ident()  { printf '{"github_username":"octocat"}\n' > "$HOME/.superhuman/global/identity.json"; }

# 1. env opt-out -> no send
setup
SUPERHUMAN_TELEMETRY=off bash "$SCRIPT" --pr-url "http://x" --outcome ok
[ -s "$CURL_LOG" ] && fail "env off should not send"
teardown

# 2. flag opt-out -> no send
setup
printf '{"enabled":false}\n' > "$HOME/.superhuman/global/telemetry.json"
bash "$SCRIPT" --pr-url "http://x" --outcome ok
[ -s "$CURL_LOG" ] && fail "flag disabled should not send"
teardown

# 3. enabled + PR -> send with pr_raised true
setup; enable; ident
bash "$SCRIPT" --pr-url "http://x/pull/1" --outcome merged_ready
grep -q 'superhuman_run'    "$CURL_LOG" || fail "missing event name"
grep -q 'octocat'           "$CURL_LOG" || fail "missing distinct_id"
grep -q '"pr_raised":true'  "$CURL_LOG" || fail "missing pr_raised true"
teardown

# 3b. enabled, no PR -> pr_raised false
setup; enable; ident
bash "$SCRIPT" --pr-url "" --outcome no_pr
grep -q '"pr_raised":false' "$CURL_LOG" || fail "missing pr_raised false"
teardown

# 4. print mode -> payload on stderr, no send
setup; enable; ident
out=$(SUPERHUMAN_TELEMETRY=print bash "$SCRIPT" --pr-url "http://x" --outcome ok 2>&1 >/dev/null)
echo "$out" | grep -q 'superhuman_run' || fail "print mode should emit payload"
[ -s "$CURL_LOG" ] && fail "print mode should not send"
teardown

# 5. unknown user fallback
setup; enable
export GH_FAIL=1
bash "$SCRIPT" --pr-url "" --outcome ok
grep -q 'unknown' "$CURL_LOG" || fail "should fall back to unknown distinct_id"
teardown

# 6. first run creates flag file
setup
bash "$SCRIPT" --pr-url "" --outcome ok 2>/dev/null
[ -f "$HOME/.superhuman/global/telemetry.json" ] || fail "first run should create flag file"
teardown

echo "OK test_usage_ping.sh"
