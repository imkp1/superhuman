#!/usr/bin/env bash
# Compile ~/.superhuman/preferences.md into GitHub search queries (repo-finder
# Step 1). Prints one `q=` qualifier string per line; the caller feeds each to
# `gh api search/repositories`.
#
# The qualifier asymmetry is the whole design, and it is measured, not assumed:
#
#   language:  repeated -> OR   `language:go language:rust` returns Go ∪ Rust
#   topic:     repeated -> AND  `topic:cli topic:terminal` returns only repos
#                               tagged BOTH — a smaller or empty set, exit 0,
#                               no error anywhere.
#
# Therefore: all languages collapse into one query, and each topic needs its own.
# Query count is |topics|. Adding a language adds zero queries. Emitting two
# `topic:` qualifiers on one line is the bug every guard in this file exists to
# prevent.
#
# No LLM in this path. Same file in, same bytes out, every run — a model in the
# query path cannot promise that, cannot be tested by a network-free CI, and
# turns a misparse into a confidently wrong scan with exit 0. Prose compiles to
# filters in /preferences, at authoring, with a human confirming, or not at all.
#
# Exit: 0 ok, 10 malformed preferences (from parse_preferences) or a query that
# fails its own guards.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=../lib/preferences.sh
. "$HERE/../lib/preferences.sh"

die() { echo "FATAL: $*" >&2; exit 10; }

# Today's queries, lifted verbatim from the agent's DEFAULT_QUERIES. A fresh
# machine with no preferences.md must scan exactly as it does today, so
# /contribute, /contribute-loop and /contribution-fleet keep working untouched.
#
# Union semantics on purpose: the topic queries carry no language and the
# language query carries no topic. Generating this from the strict
# `language AND topic` shape would silently drop a Rust ML repo and an untagged
# Java repo from a fresh machine's candidate set — a composition change for users
# who never asked for one. The strict shape is opt-in: it applies the moment
# someone writes a preferences.md, and not before.
DEFAULT_PROFILE="topic:machine-learning stars:>20000 archived:false
topic:llm stars:>5000 archived:false
topic:artificial-intelligence stars:>20000 archived:false
topic:developer-tools stars:>20000 archived:false
language:java language:python stars:>20000 archived:false"

PREFS=""
NUDGE=1
while [ $# -gt 0 ]; do
  case "$1" in
    --file)     [ $# -ge 2 ] || die "--file needs a value"; PREFS="$2"; shift 2 ;;
    --no-nudge) NUDGE=0; shift ;;
    *)          die "unknown argument: $1" ;;
  esac
done
[ -n "$PREFS" ] || PREFS="$(prefs_path)"
command -v jq >/dev/null 2>&1 || die "jq is required"

# Every emitted line passes this. The guards are here, not only in the tests,
# because each failure they catch is silent at the API: a typo'd qualifier key
# and a parenthesized OR both return total_count: 0 with exit 0, and a second
# `topic:` returns a quietly intersected set. Nothing downstream can tell any of
# them apart from a thin week for open source.
assert_query() {
  local q="$1" tok key topics=0 langs=0

  case "$q" in
    *" OR "*|*" AND "*|*"("*|*")"*)
      die "boolean operator or paren in query: '$q' (GitHub reads these as free text)" ;;
    *"-language:"*|*"-topic:"*)
      die "negated qualifier in query: '$q' (exclusion was considered and rejected)" ;;
    *".."*|*"stars:<"*)
      die "star ceiling in query: '$q' (stars is a floor; there is no ceiling)" ;;
  esac

  for tok in $q; do
    case "$tok" in
      *:*) key="${tok%%:*}" ;;
      *)   die "bare word in query: '$tok' in '$q' (free text is not a filter)" ;;
    esac
    case "$key" in
      language) langs=$((langs + 1)) ;;
      topic)    topics=$((topics + 1)) ;;
      stars|archived) ;;
      *) die "unknown qualifier key '$key' in '$q' (allowed: language, topic, stars, archived)" ;;
    esac
  done

  # A second topic: intersects rather than unions.
  [ "$topics" -le 1 ] || die "more than one topic: qualifier in '$q' — topics AND, they do not OR"
  # A query with neither is a catch-all: it admits repos matching no criterion.
  [ $((langs + topics)) -ge 1 ] || die "catch-all query (no language:, no topic:): '$q'"
}

emit() {
  local q="$1"
  assert_query "$q"
  printf '%s\n' "$q"
}

# Shown once per install, not every run: a nag you see ten times is a nag you
# stop reading. last_version.json already exists for exactly this class of
# once-per-install lifecycle state, so no new file.
nudge_once() {
  [ "$NUDGE" -eq 1 ] || return 0
  local dir="$HOME/.superhuman/global" f tmp
  f="$dir/last_version.json"
  if [ -f "$f" ] && [ "$(jq -r '.preferences_nudged // false' "$f" 2>/dev/null)" = "true" ]; then
    return 0
  fi
  echo "Using default filters (ai-ml, java, python, devtools · >20K stars; llm >5K)." >&2
  echo "Run /preferences to set your own — takes about a minute." >&2
  mkdir -p "$dir"
  tmp="$f.tmp.$$"
  if [ -f "$f" ]; then
    jq '.preferences_nudged = true' "$f" > "$tmp" 2>/dev/null && mv "$tmp" "$f" || rm -f "$tmp"
  else
    jq -n '{preferences_nudged: true}' > "$tmp" && mv "$tmp" "$f" || rm -f "$tmp"
  fi
}

# A file that exists but declares no ## Filters content (only ## Notes, or an
# empty block) means "default filters, plus advisory notes" — not a catch-all to
# reject. Fall back to DEFAULT_PROFILE. A block WITH content still goes to the
# parser below, which fails loud on a typo, so this never swallows a malformed
# filter (see the notes-only + malformed-abort cases in test_build_queries.sh).
if [ ! -f "$PREFS" ] || ! prefs_has_filters "$PREFS"; then
  nudge_once
  while IFS= read -r q; do
    [ -n "$q" ] && emit "$q"
  done <<EOF
$DEFAULT_PROFILE
EOF
  exit 0
fi

PARSED=$(parse_preferences "$PREFS") || exit 10

# One `language:` per language, joined into a single prefix. Languages are free:
# they OR inside one query, so the count never grows with them.
LANG_PREFIX=$(printf '%s' "$PARSED" | jq -r '.languages | map("language:" + .) | join(" ")')
GLOBAL_MIN=$(printf '%s' "$PARSED" | jq -r '.stars.min')

# One tab-separated line per topic entry: "<min_stars>\t<topic-or-empty>". `any`
# is reserved and compiles to the ABSENCE of a topic: qualifier — never to a
# literal topic:any. The topic goes last precisely because it can be empty: as a
# leading space-separated field it is swallowed by word splitting, and the `any`
# query vanishes with no error.
#
# A single loop, no nested loops, no `declare -A`, no `mapfile`: bash 3.2 is what
# ships on macOS, and those pass on the ubuntu runner and die there.
TAB=$(printf '\t')
TOPIC_SPEC=$(printf '%s' "$PARSED" | jq -r --argjson g "$GLOBAL_MIN" '
  .topics[] | "\(.min_stars // $g)\t\(if .topic == "any" then "" else .topic end)"')

while IFS="$TAB" read -r min topic; do
  [ -n "$min" ] || continue
  Q="$LANG_PREFIX"
  if [ -n "$topic" ]; then Q="${Q:+$Q }topic:$topic"; fi
  Q="${Q:+$Q }stars:>$min archived:false"
  emit "$Q"
done <<EOF
$TOPIC_SPEC
EOF
