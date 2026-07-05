#!/usr/bin/env bash
# usage_ping.sh --pr-url <URL|""> --outcome <STRING>
# Best-effort adoption telemetry. Sends one 'superhuman_run' event to PostHog.
# MUST never block or fail the caller: exits 0 on every path, curl is bounded.
set -uo pipefail

POSTHOG_KEY="${SUPERHUMAN_POSTHOG_KEY:-phc_C8PYp2Sjq6pfQQ8u6f3r37rqdQYnXNVgJEJGQYrDMm8y}"
POSTHOG_HOST="${SUPERHUMAN_POSTHOG_HOST:-https://us.i.posthog.com}"
GLOBAL_DIR="$HOME/.superhuman/global"
FLAG_FILE="$GLOBAL_DIR/telemetry.json"
IDENTITY_FILE="$GLOBAL_DIR/identity.json"

PR_URL=""; OUTCOME=""
while [ $# -gt 0 ]; do
  case "$1" in
    --pr-url)  PR_URL="${2:-}"; shift 2 ;;
    --outcome) OUTCOME="${2:-}"; shift 2 ;;
    *) shift ;;   # ignore unknown args; telemetry must never hard-fail
  esac
done

# 1. Env opt-out (highest precedence).
[ "${SUPERHUMAN_TELEMETRY:-}" = "off" ] && exit 0

# 2. First-run notice + persistent flag (notice via /dev/tty so it survives a
#    backgrounded/redirected caller; falls back to stderr where no tty).
if [ ! -f "$FLAG_FILE" ]; then
  mkdir -p "$GLOBAL_DIR"
  msg="superhuman records anonymous usage counts (your GitHub username, run count, PR count) to help the maintainer measure adoption. Disable with SUPERHUMAN_TELEMETRY=off — see TELEMETRY.md."
  { echo "$msg" > /dev/tty; } 2>/dev/null || echo "$msg" >&2
  printf '{"enabled":true}\n' > "$FLAG_FILE"
fi

# 3. Persistent flag opt-out.
enabled=$(jq -r 'if has("enabled") then .enabled else true end' "$FLAG_FILE" 2>/dev/null || echo true)
[ "$enabled" = "false" ] && exit 0

# 4. Resolve GitHub username (cache -> gh -> "unknown").
username=""
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

# 5. Plugin version.
version=$(jq -r '.version // "unknown"' \
  "${CLAUDE_PLUGIN_ROOT:-}/.claude-plugin/plugin.json" 2>/dev/null || echo "unknown")

# 6. pr_raised.
if [ -n "$PR_URL" ]; then pr_raised=true; else pr_raised=false; fi

# 7. Build payload.
payload=$(jq -nc \
  --arg key "$POSTHOG_KEY" --arg uid "$username" \
  --arg out "$OUTCOME" --arg ver "$version" \
  --argjson pr "$pr_raised" \
  '{api_key:$key, event:"superhuman_run", distinct_id:$uid,
    properties:{pr_raised:$pr, outcome:$out, version:$ver}}' 2>/dev/null) || exit 0

# 8. Print mode (transparency / dry-run).
if [ "${SUPERHUMAN_TELEMETRY:-}" = "print" ]; then
  echo "$payload" >&2
  exit 0
fi

# 9. Send: bounded, silent, never fails the caller.
curl -sf --max-time 3 -X POST \
  -H 'Content-Type: application/json' \
  -d "$payload" \
  "$POSTHOG_HOST/i/v0/e/" >/dev/null 2>&1 || true

exit 0
