#!/usr/bin/env bash
# pr_body_with_attribution.sh
# Reads a PR body on stdin, writes it to stdout normalized:
#   1. scrub any model-authored attribution line (always, regardless of the flag)
#   2. if SUPERHUMAN_ATTRIBUTION is enabled, append the canonical Superhuman footer
#      (disabling values: off/false/0/no, case-insensitive)
# The canonical footer is the single source of truth: scrub strips it too, so
# re-appending is idempotent and there is never a rogue or double attribution.
# PR-body only; commits are never touched (the single-author commit rule in
# agents/builder.md is commit-scoped and unchanged).
set -euo pipefail
: "${CLAUDE_PLUGIN_ROOT:?CLAUDE_PLUGIN_ROOT must be set}"

FALLBACK_URL='https://github.com/gaurav0107/superhuman'

# Remove any whole-line model-authored attribution, then collapse the blank/---
# runs the removal leaves behind. Matching is case-insensitive; a line is
# removed only when the entire line is attribution (verb + tool/agent name) or
# an explicit attribution artifact — so legitimate prose is preserved.
scrub_attribution() {
  awk '
  function is_attr(line,   lraw, a) {
    lraw = tolower(line)
    if (index(lraw, "opened with [superhuman]"))        return 1
    if (index(lraw, "github.com/gaurav0107/superhuman")) return 1
    if (index(lraw, "noreply@anthropic.com"))            return 1
    if (index(lraw, "claude.ai/code"))                   return 1
    if (index(lraw, "claude.com/claude-code"))           return 1
    if (index(line, "🤖") && index(lraw, "generated with")) return 1
    a = lraw
    sub(/^[[:space:]]+/, "", a)
    gsub(/^(>[[:space:]]*)+/, "", a)
    sub(/^<sub>[[:space:]]*/, "", a)
    if (a ~ /^co-authored-by:/) return 1
    if (lraw ~ /(prepared|generated|opened|created|made|built|authored|written|produced|assisted|with assistance)/ &&
        lraw ~ /(superhuman|claude|anthropic|ai agent|contribution agent|contribution plugin)/) return 1
    return 0
  }
  { lines[NR] = $0 }
  END {
    m = 0
    for (i = 1; i <= NR; i++) if (!is_attr(lines[i])) { m++; keep[m] = lines[i] }
    # collapse consecutive blank lines
    o = 0; prevblank = 0
    for (i = 1; i <= m; i++) {
      isblank = (keep[i] ~ /^[[:space:]]*$/)
      if (isblank && prevblank) continue
      o++; out[o] = keep[i]; prevblank = isblank
    }
    # trim trailing blanks, then drop an orphaned trailing horizontal rule
    while (o > 0 && out[o] ~ /^[[:space:]]*$/) o--
    if (o > 0) {
      t = out[o]; sub(/^[[:space:]]+/, "", t); sub(/[[:space:]]+$/, "", t)
      if (t ~ /^-{3,}$/) { o--; while (o > 0 && out[o] ~ /^[[:space:]]*$/) o-- }
    }
    for (i = 1; i <= o; i++) { printf "%s", out[i]; if (i < o) printf "\n" }
  }
  '
}

BODY="$(cat)"
SCRUBBED="$(printf '%s' "$BODY" | scrub_attribution)"

# Disclosure is ON unless explicitly disabled. When disabled, emit the scrubbed
# body (no footer) — "off" must mean no attribution at all, including rogue lines.
case "$(printf '%s' "${SUPERHUMAN_ATTRIBUTION:-on}" | tr '[:upper:]' '[:lower:]')" in
  off|false|0|no)
    printf '%s' "$SCRUBBED"
    exit 0
    ;;
esac

# Single source of truth for the repo URL: plugin.json, with a constant fallback.
PLUGIN_JSON="${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json"
REPO_URL="$FALLBACK_URL"
if [ -f "$PLUGIN_JSON" ]; then
  URL_FROM_JSON="$(jq -r '.homepage // .repository // empty' "$PLUGIN_JSON" 2>/dev/null || true)"
  [ -n "$URL_FROM_JSON" ] && REPO_URL="$URL_FROM_JSON"
fi

printf '%s\n\n---\n🤖 Opened with [Superhuman](%s), an open-source contribution agent.\n' \
  "$SCRUBBED" "$REPO_URL"
