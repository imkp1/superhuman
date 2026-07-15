#!/usr/bin/env bash
# curated_list_filter.sh — is this candidate a code repo, or a curated list?
#
# Reads one Step 1 search record (a single repo object) on stdin.
#   exit 0  = code repo, keep it
#   exit 1  = curated list / book / roadmap, hard skip
#   exit 10 = config error, not a verdict
#
# Why this exists. Deleting the category bonus was right: with filtering
# server-side every candidate matches by construction, so a bonus for matching is
# a constant added to every row and ranks nothing. But that bonus was also, by
# accident, the only term that knew whether a repo contained code. Without it the
# rubric floats link-lists to the top — they answer issues fast and merge outside
# PRs readily, so they score *well* on responsiveness (35%) and outside-contributor
# track (25%), 60% of the weight, while offering nothing to contribute. On a
# default-profile scan free-programming-books (89), project-based-learning (80) and
# public-apis (77) all outranked every real code repo; only the Step 4 issue check
# kept them off the shortlist.
#
# A list is not a repo we score badly. It is a repo we do not score at all.
#
# Strong vs weak signals, deliberately. A flat keyword match is how the AI-policy
# check came to hard-skip yt-dlp: `ai` appears inside "chains". A hard skip has no
# appeal, so a single weak keyword must never trigger one — `education` and
# `resources` tag plenty of real code. The bar is one strong signal, or two weak.
set -euo pipefail

EX_CONFIG=10

command -v jq >/dev/null 2>&1 || {
  echo "curated_list_filter.sh: CONFIG ERROR: jq not found on PATH." >&2
  exit "$EX_CONFIG"
}

CANDIDATE=$(cat)
[ -n "$CANDIDATE" ] || {
  echo "curated_list_filter.sh: CONFIG ERROR: empty candidate on stdin." >&2
  exit "$EX_CONFIG"
}
printf '%s' "$CANDIDATE" | jq -e . >/dev/null 2>&1 || {
  echo "curated_list_filter.sh: CONFIG ERROR: candidate is not valid JSON." >&2
  exit "$EX_CONFIG"
}

NAME=$(printf '%s' "$CANDIDATE" \
  | jq -r '((.name // (.full_name // "" | split("/") | last)) // "") | ascii_downcase')
LANG=$(printf '%s' "$CANDIDATE" | jq -r '(.language // "") | ascii_downcase')
TOPICS=$(printf '%s' "$CANDIDATE" | jq -r '(.topics // [])[] | ascii_downcase')

# Sufficient alone.
#
# Pedagogy topics are strong, not weak: a repo tagged `tutorial` or `course` exists
# to be read, not patched, and a course carries exactly one such tag, so a two-weak
# bar never fires on it. No real library on a go/python scan carries any of them.
STRONG_TOPICS='awesome awesome-list awesome-lists curated-list cheatsheet cheatsheets interview-questions roadmap free-programming-books tutorial tutorials course courses educational teaching learning-path study-plan'
# Each of these also tags real code, so two are required.
WEAK_TOPICS='list lists resources resource books book learning education guide guides collection from-scratch'

strong=""
weak=0

# A repo with no primary language has no code to contribute to: GitHub reports
# `language: null` for a tree of Markdown, which is precisely what a list is.
#
# Dead whenever the profile pins `languages:` — every candidate then arrives from a
# query carrying `language:go language:python`, so `.language` cannot be null by
# construction. It still fires on a profile with no `languages:` line. Do not treat
# it as this filter's backbone: on a language-pinned scan the topic signals are.
case "$LANG" in
  ''|null|markdown) strong="language=${LANG:-null}" ;;
esac

case "$NAME" in
  awesome|awesome-*|awesome_*) strong="${strong:-name=$NAME}" ;;
esac

# Read topics line-by-line: zsh does not word-split an unquoted expansion, so
# `for t in $TOPICS` would iterate once over the whole blob.
while IFS= read -r t; do
  [ -n "$t" ] || continue
  for s in $STRONG_TOPICS; do
    [ "$t" = "$s" ] && strong="${strong:-topic=$t}"
  done
  for w in $WEAK_TOPICS; do
    [ "$t" = "$w" ] && weak=$((weak + 1))
  done
done <<EOF
$TOPICS
EOF

if [ -n "$strong" ]; then
  echo "SKIP: curated list, not a code repo ($strong)" >&2
  exit 1
fi
if [ "$weak" -ge 2 ]; then
  echo "SKIP: curated list, not a code repo ($weak weak list signals in topics)" >&2
  exit 1
fi

exit 0
