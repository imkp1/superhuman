#!/usr/bin/env bash
# User search preferences (~/.superhuman/preferences.md).
#
# The file has two halves and they promise different things:
#
#   ## Filters   mechanical. Parsed here, compiled 1:1 into GitHub search
#                qualifiers by scripts/repo-finder/build_queries.sh.
#   ## Notes     prose. Never parsed. Read by the agent at tie-breaks and issue
#                selection only; it may not touch a numeric score or a query.
#
# Only the Filters block is read here. Everything else in the file is prose and
# is legal by construction — a Notes sentence like "languages are fun" is not a
# filter and must not be mistaken for one.
#
# No yq: scripts/profiler/parse_workflows.sh already depends on it and it is not
# installed on a stock macOS box. CI installs it, so a second dependency would go
# green in CI and dead on the user's laptop. awk + jq are hard requirements.
#
# Exit 10 = malformed preferences. Never a silent skip: a mistyped `langauges: go`
# that parses to "no language filter" produces a confidently wrong scan with
# exit 0, which is the failure class this file exists to prevent.

PREFS_MAX_TOPICS=20

prefs_path() {
  echo "${SUPERHUMAN_PREFS:-$HOME/.superhuman/preferences.md}"
}

# Emit "key<TAB>value" for each line of the `## Filters` block. A line in that
# block that is not `key: value` is an error, not prose — prose belongs in Notes.
_prefs_filter_lines() {
  awk '
    /^##[ \t]+/ { inblk = ($0 ~ /^##[ \t]*[Ff]ilters[ \t]*$/); next }
    !inblk      { next }
    /^[ \t]*$/  { next }
    /^[ \t]*#/  { next }
    {
      line = $0
      gsub(/^[ \t]+|[ \t]+$/, "", line)
      i = index(line, ":")
      if (i == 0) { print "ERR\t" line; exit }
      key = substr(line, 1, i - 1)
      val = substr(line, i + 1)
      gsub(/^[ \t]+|[ \t]+$/, "", key)
      gsub(/^[ \t]+|[ \t]+$/, "", val)
      print key "\t" val
    }
  ' "$1"
}

# Comma-separated list -> one trimmed entry per line. Whitespace inside an entry
# is preserved on purpose; the charset guards below reject it.
_prefs_split() {
  printf '%s' "$1" | tr ',' '\n' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | grep -v '^$' || true
}

# parse_preferences <file> -> JSON on stdout
#
#   {"languages": ["go","rust"],
#    "topics": [{"topic":"backend"}, {"topic":"llm","min_stars":5000}, {"topic":"any"}],
#    "stars": {"min": 2000}}
#
# `any` is reserved: it compiles to a query with no `topic:` qualifier, never to
# a literal `topic:any` (GitHub has a real `any` topic; this will never mean it).
# An omitted `topics:` line is exactly `topics: any` — one mechanism, not two.
parse_preferences() {
  local file="${1:-$(prefs_path)}"
  [ -f "$file" ] || { echo "FATAL: preferences file not found: $file" >&2; return 10; }

  local key val langs="" topics="" stars=""
  local seen_langs="" seen_topics="" seen_stars=""
  local tab
  tab=$(printf '\t')

  while IFS="$tab" read -r key val; do
    [ -n "$key" ] || continue
    case "$key" in
      ERR)
        echo "FATAL: not a 'key: value' line in ## Filters: '$val'" >&2
        echo "       Prose belongs under ## Notes." >&2
        return 10 ;;
      languages)
        [ -z "$seen_langs" ] || { echo "FATAL: duplicate 'languages:' key in ## Filters" >&2; return 10; }
        seen_langs=1; langs="$val" ;;
      topics)
        [ -z "$seen_topics" ] || { echo "FATAL: duplicate 'topics:' key in ## Filters" >&2; return 10; }
        seen_topics=1; topics="$val" ;;
      stars)
        [ -z "$seen_stars" ] || { echo "FATAL: duplicate 'stars:' key in ## Filters" >&2; return 10; }
        seen_stars=1; stars="$val" ;;
      *)
        echo "FATAL: unknown key in ## Filters: '$key' (expected: languages, topics, stars)" >&2
        return 10 ;;
    esac
  done <<EOF
$(_prefs_filter_lines "$file")
EOF

  # stars is a floor and only a floor. A range (2000-60000) is malformed, not a
  # quietly honored ceiling: a ceiling deletes exactly the repos the
  # responsiveness scorer exists to judge, and it does it with no error.
  if [ -n "$seen_stars" ]; then
    case "$stars" in
      ''|*[!0-9]*)
        echo "FATAL: stars must be a bare integer floor, got '$stars'." >&2
        echo "       There is no ceiling: no ranges (2000-60000), no '>' prefix." >&2
        return 10 ;;
    esac
  else
    stars=2000
  fi

  # Entries are comma-separated, and the split keeps whitespace INSIDE an entry.
  # That is what catches `languages: go OR rust`: the operator stays glued to its
  # entry, trips the charset guard, and exits 10. Split on whitespace too and
  # `OR` becomes a third language — a query GitHub answers with total_count: 0
  # and exit 0.
  local lang_list="" tok
  while IFS= read -r tok; do
    [ -n "$tok" ] || continue
    case "$tok" in
      [A-Za-z0-9]*) ;;
      *) echo "FATAL: invalid language: '$tok'" >&2; return 10 ;;
    esac
    case "$tok" in
      *[!A-Za-z0-9+#._-]*)
        echo "FATAL: invalid character in language: '$tok' (one language per comma)" >&2
        return 10 ;;
    esac
    lang_list="$lang_list $tok"
  done <<EOF
$(_prefs_split "$langs")
EOF

  local topic_list="" name floor n=0 has_any=0
  while IFS= read -r tok; do
    [ -n "$tok" ] || continue
    tok=$(printf '%s' "$tok" | tr '[:upper:]' '[:lower:]')
    name="${tok%%:*}"
    floor=""
    case "$tok" in *:*) floor="${tok#*:}" ;; esac
    [ "$name" = any ] && has_any=1

    case "$name" in
      [a-z0-9]*) ;;
      *) echo "FATAL: invalid topic: '$tok'" >&2; return 10 ;;
    esac
    case "$name" in
      *[!a-z0-9._-]*)
        echo "FATAL: invalid character in topic: '$name' (one topic per comma)" >&2
        return 10 ;;
    esac
    case "$tok" in
      *:*)
        case "$floor" in
          ''|*[!0-9]*)
            echo "FATAL: topic star floor must be an integer, got '$tok' (want e.g. llm:5000)" >&2
            return 10 ;;
        esac ;;
    esac

    n=$((n + 1))
    if [ "$n" -gt "$PREFS_MAX_TOPICS" ]; then
      echo "WARN: more than $PREFS_MAX_TOPICS topics; using the first $PREFS_MAX_TOPICS." >&2
      echo "      Query count is topic count, and GitHub search allows 30/minute." >&2
      break
    fi
    topic_list="$topic_list ${name}${floor:+:$floor}"
  done <<EOF
$(_prefs_split "$topics")
EOF

  # An omitted topics line is the same catch-all as an explicit `any`.
  [ -n "$topic_list" ] || { topic_list=" any"; has_any=1; }

  # `any` compiles to a query with no topic: qualifier. With no languages either,
  # that query carries nothing but stars — a catch-all matching every repo on
  # GitHub, which is the noise source this whole design exists to remove.
  #
  # Reject it here, at the file, rather than downstream at the query: build_queries
  # would emit the other topics first and only then abort, leaving a partial
  # candidate set on stdout. And /preferences round-trips through this parser, so
  # catching it here means an unusable profile can never reach disk.
  #
  # Track `any` by name, not by substring: `any:5000` carries a floor and so is
  # stored as `any:5000`, which no ` any ` match would catch — but build_queries
  # strips the topic: qualifier on `.topic == "any"` regardless of the floor, so
  # the floored form is exactly as much a catch-all as the bare one.
  if [ "$has_any" -eq 1 ] && [ -z "$lang_list" ]; then
    echo "FATAL: 'topics: any' with no languages is a catch-all — it matches every repo on GitHub." >&2
    echo "       Add a 'languages:' line, or drop 'any' and name the topics you want." >&2
    return 10
  fi

  jq -nc \
    --arg langs "$lang_list" \
    --arg topics "$topic_list" \
    --argjson stars "$stars" '
    {
      languages: ($langs | split(" ") | map(select(length > 0))),
      topics: ($topics | split(" ") | map(select(length > 0)) | map(
        if test(":")
        then (split(":") | {topic: .[0], min_stars: (.[1] | tonumber)})
        else {topic: .}
        end)),
      stars: {min: $stars}
    }'
}

# One line at the top of every scan, so the active filter is never a mystery.
prefs_summary() {
  local file="${1:-$(prefs_path)}"
  if [ ! -f "$file" ]; then
    # The floors are not uniform: llm sits at >5000 because LLM repos are younger
    # and a 20K floor erases the category. Say so rather than round it off — a
    # summary that misstates the active filter is worse than none.
    echo "filters: default profile (machine-learning, artificial-intelligence, developer-tools >20000 · llm >5000 · java, python >20000)"
    return 0
  fi
  local json
  json=$(parse_preferences "$file") || return 10
  printf '%s' "$json" | jq -r '
    "filters: languages=" + (if (.languages | length) == 0 then "any" else (.languages | join(",")) end)
    + " · topics=" + (.topics | map(.topic + (if .min_stars then ">\(.min_stars)" else "" end)) | join(","))
    + " · stars >\(.stars.min)"'
}
