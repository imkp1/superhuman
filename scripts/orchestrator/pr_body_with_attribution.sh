#!/usr/bin/env bash
# pr_body_with_attribution.sh
# Reads a PR body on stdin, writes it to stdout with a Superhuman origin-disclosure
# footer appended — UNLESS SUPERHUMAN_ATTRIBUTION is a disabling value
# (off/false/0/no, case-insensitive). Idempotent: never appends the footer twice.
# PR-body only; commits are never touched (the single-author commit rule in
# agents/builder.md is commit-scoped and unchanged).
set -euo pipefail
: "${CLAUDE_PLUGIN_ROOT:?CLAUDE_PLUGIN_ROOT must be set}"

MARKER='Opened with [Superhuman]'
FALLBACK_URL='https://github.com/gaurav0107/superhuman'

# Read the entire base body from stdin.
BODY="$(cat)"

# Disclosure is ON unless explicitly disabled.
case "$(printf '%s' "${SUPERHUMAN_ATTRIBUTION:-on}" | tr '[:upper:]' '[:lower:]')" in
  off|false|0|no)
    printf '%s' "$BODY"
    exit 0
    ;;
esac

# Idempotency: if the footer is already present, emit unchanged.
if printf '%s' "$BODY" | grep -qF "$MARKER"; then
  printf '%s' "$BODY"
  exit 0
fi

# Single source of truth for the repo URL: plugin.json, with a constant fallback.
PLUGIN_JSON="${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json"
REPO_URL="$FALLBACK_URL"
if [ -f "$PLUGIN_JSON" ]; then
  URL_FROM_JSON="$(jq -r '.homepage // .repository // empty' "$PLUGIN_JSON" 2>/dev/null || true)"
  [ -n "$URL_FROM_JSON" ] && REPO_URL="$URL_FROM_JSON"
fi

printf '%s\n\n---\n🤖 Opened with [Superhuman](%s), an open-source contribution agent.\n' \
  "$BODY" "$REPO_URL"
