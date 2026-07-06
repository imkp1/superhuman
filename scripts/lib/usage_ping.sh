#!/usr/bin/env bash
# usage_ping.sh --pr-url <URL|""> --outcome <STRING>
# Best-effort adoption telemetry. Sends one 'superhuman_run' event to PostHog.
# MUST never block or fail the caller: exits 0 on every path, curl is bounded.
set -uo pipefail

# shellcheck source=scripts/lib/telemetry_common.sh
. "$(dirname "$0")/telemetry_common.sh"

PR_URL=""; OUTCOME=""
while [ $# -gt 0 ]; do
  case "$1" in
    --pr-url)  PR_URL="${2:-}"; shift 2 ;;
    --outcome) OUTCOME="${2:-}"; shift 2 ;;
    *) shift ;;   # ignore unknown args; telemetry must never hard-fail
  esac
done

# Opt-out gate (env + persistent flag; creates flag + notice on first run).
th_opted_out && exit 0

username=$(th_username)
version=$(th_version)
if [ -n "$PR_URL" ]; then pr_raised=true; else pr_raised=false; fi

payload=$(jq -nc \
  --arg key "$POSTHOG_KEY" --arg uid "$username" \
  --arg out "$OUTCOME" --arg ver "$version" \
  --argjson pr "$pr_raised" \
  '{api_key:$key, event:"superhuman_run", distinct_id:$uid,
    properties:{pr_raised:$pr, outcome:$out, version:$ver}}' 2>/dev/null) || exit 0

th_send "$payload"
exit 0
