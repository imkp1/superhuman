#!/usr/bin/env bash
# usage_event.sh --command <name>
# Best-effort adoption telemetry. Sends one 'superhuman_used' event, and on
# a version change one 'superhuman_lifecycle' event (install|update).
# MUST never block or fail the caller: exits 0 on every path, curl is bounded.
set -uo pipefail

# shellcheck source=scripts/lib/telemetry_common.sh
. "$(dirname "$0")/telemetry_common.sh"

COMMAND=""
while [ $# -gt 0 ]; do
  case "$1" in
    --command) COMMAND="${2:-}"; shift 2 ;;
    *) shift ;;   # ignore unknown args; telemetry must never hard-fail
  esac
done

# Opt-out gate (env + persistent flag; creates flag + notice on first run).
th_opted_out && exit 0

username=$(th_username)
version=$(th_version)

# 1. superhuman_used — one per command invocation.
used=$(jq -nc \
  --arg key "$POSTHOG_KEY" --arg uid "$username" \
  --arg cmd "$COMMAND" --arg ver "$version" \
  '{api_key:$key, event:"superhuman_used", distinct_id:$uid,
    properties:{command:$cmd, version:$ver}}' 2>/dev/null) || exit 0
th_send "$used"

# 2. superhuman_lifecycle — only on install (no cache) or update (version
#    changed). No native installer hook exists, so we infer from a cached
#    last-seen version.
LAST_VERSION_FILE="$GLOBAL_DIR/last_version.json"
prev=""; kind=""
if [ ! -f "$LAST_VERSION_FILE" ]; then
  kind="install"
else
  prev=$(jq -r '.version // empty' "$LAST_VERSION_FILE" 2>/dev/null || echo "")
  if [ -n "$prev" ] && [ "$prev" != "$version" ]; then
    kind="update"
  fi
fi

if [ -n "$kind" ]; then
  life=$(jq -nc \
    --arg key "$POSTHOG_KEY" --arg uid "$username" \
    --arg kind "$kind" --arg ver "$version" --arg prev "$prev" \
    '{api_key:$key, event:"superhuman_lifecycle", distinct_id:$uid,
      properties:{kind:$kind, version:$ver, prev_version:$prev}}' 2>/dev/null)
  if [ -n "$life" ]; then
    th_send "$life"
    mkdir -p "$GLOBAL_DIR"
    printf '{"version":"%s"}\n' "$version" > "$LAST_VERSION_FILE"
  fi
fi

exit 0
