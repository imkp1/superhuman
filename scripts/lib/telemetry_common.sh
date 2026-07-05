#!/usr/bin/env bash
# telemetry_common.sh — sourced helpers shared by usage_ping.sh and
# usage_event.sh. Defines constants + functions only; executes nothing at
# source time. Every path is best-effort and must never fail a caller.
# See TELEMETRY.md for the opt-out contract and event catalog.

POSTHOG_KEY="${SUPERHUMAN_POSTHOG_KEY:-phc_C8PYp2Sjq6pfQQ8u6f3r37rqdQYnXNVgJEJGQYrDMm8y}"
POSTHOG_HOST="${SUPERHUMAN_POSTHOG_HOST:-https://us.i.posthog.com}"
GLOBAL_DIR="$HOME/.superhuman/global"
FLAG_FILE="$GLOBAL_DIR/telemetry.json"
IDENTITY_FILE="$GLOBAL_DIR/identity.json"

# th_opted_out: return 0 when telemetry must NOT send, 1 when enabled.
# Side effect: on first ever run, prints the one-time notice and creates
# the flag file (enabled by default — opt-out model).
th_opted_out() {
  [ "${SUPERHUMAN_TELEMETRY:-}" = "off" ] && return 0
  if [ ! -f "$FLAG_FILE" ]; then
    mkdir -p "$GLOBAL_DIR"
    local msg="superhuman records basic usage (a per-run event with your GitHub username and whether a PR was opened) to help the maintainer measure adoption. Disable with SUPERHUMAN_TELEMETRY=off — see TELEMETRY.md."
    { echo "$msg" > /dev/tty; } 2>/dev/null || echo "$msg" >&2
    printf '{"enabled":true}\n' > "$FLAG_FILE"
  fi
  local enabled
  enabled=$(jq -r 'if has("enabled") then .enabled else true end' "$FLAG_FILE" 2>/dev/null || echo true)
  [ "$enabled" = "false" ] && return 0
  return 1
}

# th_username: identity cache -> gh -> "unknown". Caches on gh success.
th_username() {
  local username=""
  if [ -f "$IDENTITY_FILE" ]; then
    username=$(jq -r '.github_username // empty' "$IDENTITY_FILE" 2>/dev/null || echo "")
  fi
  if [ -z "$username" ] && command -v gh >/dev/null 2>&1; then
    username=$(gh api user --jq '.login' 2>/dev/null || echo "")
    if [ -n "$username" ]; then
      mkdir -p "$GLOBAL_DIR"
      printf '{"github_username":"%s"}\n' "$username" > "$IDENTITY_FILE"
    fi
  fi
  [ -z "$username" ] && username="unknown"
  printf '%s' "$username"
}

# th_version: plugin.json .version -> "unknown".
th_version() {
  jq -r '.version // "unknown"' \
    "${CLAUDE_PLUGIN_ROOT:-}/.claude-plugin/plugin.json" 2>/dev/null || echo "unknown"
}

# th_send <json>: print mode -> stderr (no send); else bounded silent curl.
th_send() {
  local payload="$1"
  if [ "${SUPERHUMAN_TELEMETRY:-}" = "print" ]; then
    echo "$payload" >&2
    return 0
  fi
  curl -sf --max-time 3 -X POST \
    -H 'Content-Type: application/json' \
    -d "$payload" \
    "$POSTHOG_HOST/i/v0/e/" >/dev/null 2>&1 || true
}
