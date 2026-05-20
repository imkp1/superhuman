#!/usr/bin/env bash
# reputation_gate.sh --repo OWNER/REPO [--now ISO_TS]
# Exit 0 = eligible. 1 = blocklisted. 2 = in cooldown. 3 = locked.
# Replaces three inline duplicates: opensource-contributor.md Phase 0,
# repo-finder.md, commands/contribution-fleet.md:80-95 (audit §14).
set -euo pipefail
: "${CLAUDE_PLUGIN_ROOT:?CLAUDE_PLUGIN_ROOT must be set}"
source "${CLAUDE_PLUGIN_ROOT}/scripts/lib/state.sh"

REPO=""
NOW=""
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) REPO="$2"; shift 2 ;;
    --now)  NOW="$2";  shift 2 ;;
    *) echo "reputation_gate.sh: unknown arg: $1" >&2; exit 2 ;;
  esac
done
[ -z "$REPO" ] && { echo "--repo required" >&2; exit 2; }
[ -z "$NOW" ]  && NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)

GD=$(global_dir)
BL="$GD/repo_blocklist.json"
CD="$GD/repo_cooldown.json"

# Blocklist: highest authority
if [ -f "$BL" ]; then
  reason=$(jq -r --arg r "$REPO" --arg now "$NOW" '
    .blocked[]? | select(.repo == $r)
    | select(.expires_at == null or .expires_at > $now)
    | .reason' "$BL" 2>/dev/null | head -1)
  if [ -n "$reason" ]; then
    echo "BLOCKED: $REPO — $reason"
    exit 1
  fi
fi

# Cooldown
if [ -f "$CD" ]; then
  until_ts=$(jq -r --arg r "$REPO" '
    .cooldowns[]? | select(.repo == $r) | .cooldown_until // empty' \
    "$CD" 2>/dev/null | head -1)
  if [ -n "$until_ts" ] && [ "$until_ts" \> "$NOW" ]; then
    echo "COOLDOWN: $REPO until $until_ts"
    exit 2
  fi
fi

# Active lock
SD=$(state_dir "$REPO")
CUR="$SD/current_contribution.json"
if [ -f "$CUR" ]; then
  holder=$(jq -r '.lock_holder // empty' "$CUR" 2>/dev/null)
  if [ -n "$holder" ] && [ "$holder" != "null" ]; then
    echo "LOCKED: $REPO — held by $holder"
    exit 3
  fi
fi

echo "ELIGIBLE: $REPO"
exit 0
