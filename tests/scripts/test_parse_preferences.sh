#!/usr/bin/env bash
# parse_preferences(): the `## Filters` block -> JSON, and everything else is prose.
#
# The contract under test is that a malformed filter is LOUD. A mistyped
# `langauges: go` that parses to "no language filter" produces a confidently
# wrong scan with exit 0 — the failure class the whole design exists to remove.
set -uo pipefail
CLAUDE_PLUGIN_ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)"
export CLAUDE_PLUGIN_ROOT
# shellcheck source=../../scripts/lib/preferences.sh
. "$CLAUDE_PLUGIN_ROOT/scripts/lib/preferences.sh"

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

fail() { echo "FAIL: $*"; exit 1; }

write() { cat > "$tmpdir/$1.md"; }

# rc10 <name> <label> — a malformed file must exit 10, never emit a partial filter
rc10() {
  local out rc
  out=$(parse_preferences "$tmpdir/$1.md" 2>&1); rc=$?
  [ "$rc" = "10" ] || fail "$2: want exit 10, got $rc (output: $out)"
}

# 1. A Go+backend block yields the expected JSON, and prose is untouched by it.
write basic <<'EOF'
# My superhuman preferences

## Filters
languages: go, rust
topics: backend, llm:5000, any
stars: 2000

## Notes
I need llm repos having >5k stars.
languages are fun.
Prefer small focused libraries over sprawling frameworks.
EOF
J=$(parse_preferences "$tmpdir/basic.md") || fail "basic: parse failed"
[ "$(printf '%s' "$J" | jq -c '.languages')" = '["go","rust"]' ] \
  || fail "basic languages: $J"
[ "$(printf '%s' "$J" | jq -c '.topics')" = '[{"topic":"backend"},{"topic":"llm","min_stars":5000},{"topic":"any"}]' ] \
  || fail "basic topics: $J"
[ "$(printf '%s' "$J" | jq -r '.stars.min')" = "2000" ] || fail "basic stars: $J"

# 12. Prose survives the parser. `languages are fun` under ## Notes is a sentence,
# not a filter: it must neither parse as a `languages:` key nor exit 10. The
# advisory half of the file is always legal.
[ "$(printf '%s' "$J" | jq -c '.languages')" = '["go","rust"]' ] \
  || fail "prose leaked into the filters: $J"

# 16. jq precedence is exercised on non-empty input — an empty-input test hides
# exactly the crash that shipped in PR 26.
[ "$(printf '%s' "$J" | jq -r '.topics | length')" = "3" ] || fail "topics length: $J"

# 1b. A mistyped key is an error, not an unfiltered scan.
write typo <<'EOF'
## Filters
langauges: go
EOF
rc10 typo "mistyped key"

# A line in ## Filters that is not `key: value` is an error there — prose has a
# home and it is ## Notes.
write prose_in_filters <<'EOF'
## Filters
I would like some Go repos please
EOF
rc10 prose_in_filters "prose inside the Filters block"

# 14. stars is a floor. A range is malformed, never a quietly honored ceiling:
# a ceiling deletes the repos the responsiveness scorer exists to judge.
write range <<'EOF'
## Filters
languages: go
stars: 2000-60000
EOF
rc10 range "star range"

write gt <<'EOF'
## Filters
stars: >2000
EOF
rc10 gt "stars with a > prefix"

# A non-numeric per-topic floor is malformed, not a silently dropped qualifier.
write floor <<'EOF'
## Filters
topics: llm:lots
EOF
rc10 floor "non-numeric topic floor"

# Charset guard: this is what keeps ` OR ` and parens out of an emitted query.
# They are not errors at the API — they return total_count: 0 with exit 0.
write boolean <<'EOF'
## Filters
languages: go OR rust
EOF
rc10 boolean "boolean operator in a language list"

write parens <<'EOF'
## Filters
topics: (backend)
EOF
rc10 parens "parens in a topic list"

write negated <<'EOF'
## Filters
topics: -blockchain
EOF
rc10 negated "negated topic"

# Duplicate keys: last-wins would silently discard a filter the user wrote.
write dupe <<'EOF'
## Filters
languages: go
languages: rust
EOF
rc10 dupe "duplicate languages key"

# 9b. An omitted `topics:` line IS `topics: any` — one mechanism, not two rules.
write notopics <<'EOF'
## Filters
languages: go
EOF
J=$(parse_preferences "$tmpdir/notopics.md") || fail "notopics: parse failed"
[ "$(printf '%s' "$J" | jq -c '.topics')" = '[{"topic":"any"}]' ] \
  || fail "omitted topics must equal 'any': $J"
[ "$(printf '%s' "$J" | jq -r '.stars.min')" = "2000" ] \
  || fail "omitted stars must default to the form's 2000 floor: $J"

# A profile with no languages is legal: topic ∈ {…}, any language.
write nolangs <<'EOF'
## Filters
topics: cli
stars: 500
EOF
J=$(parse_preferences "$tmpdir/nolangs.md") || fail "nolangs: parse failed"
[ "$(printf '%s' "$J" | jq -c '.languages')" = '[]' ] || fail "nolangs: $J"

# …but `any` with no languages is not. `any` compiles to a query with no topic:
# qualifier, so with no language either it carries nothing but stars — a
# catch-all matching every repo on GitHub.
#
# Reject it at the file, not downstream at the query: build_queries would emit the
# other topics first and only then abort, leaving a partial candidate set on
# stdout. /preferences round-trips through this parser, so an unusable profile
# cannot reach disk.
write anynolangs <<'EOF'
## Filters
topics: backend, any
stars: 2000
EOF
rc10 anynolangs "'any' with no languages is a catch-all"

# A star floor does not disqualify the catch-all: `any:5000` still compiles to a
# query with no topic: qualifier, so with no language it is `stars:>5000` alone —
# every repo above the floor. The guard must key on the name, not the ` any `
# substring, which `any:5000` would slip past.
write anyfloornolangs <<'EOF'
## Filters
topics: backend, any:5000
stars: 2000
EOF
rc10 anyfloornolangs "'any:<floor>' with no languages is a catch-all"

# Same file with a language is fine — `any` is only a catch-all when nothing else
# constrains the query.
write anywithlang <<'EOF'
## Filters
languages: go
topics: backend, any
stars: 2000
EOF
parse_preferences "$tmpdir/anywithlang.md" >/dev/null \
  || fail "'any' with a language must be legal"

# An empty Filters block is `topics: any` with no languages — the same catch-all.
write emptyfilters <<'EOF'
## Filters

## Notes
just some prose
EOF
rc10 emptyfilters "an empty Filters block is a catch-all"

# 13. Topic cap: query count IS topic count, and GitHub search allows 30/minute.
# Languages are uncapped — they OR inside one query and cost nothing.
{
  echo "## Filters"
  printf 'topics: '
  i=1
  while [ "$i" -le 25 ]; do
    printf 't%s' "$i"
    [ "$i" -lt 25 ] && printf ', '
    i=$((i + 1))
  done
  echo
} > "$tmpdir/manytopics.md"
J=$(parse_preferences "$tmpdir/manytopics.md" 2>/dev/null) || fail "manytopics: parse failed"
[ "$(printf '%s' "$J" | jq -r '.topics | length')" = "20" ] \
  || fail "topic cap: want 20, got $(printf '%s' "$J" | jq -r '.topics | length')"

# Case folding: GitHub topics are lowercase. "Backend" is the same filter.
write case <<'EOF'
## Filters
topics: Backend
EOF
J=$(parse_preferences "$tmpdir/case.md")
[ "$(printf '%s' "$J" | jq -r '.topics[0].topic')" = "backend" ] || fail "case fold: $J"

# A missing file is a config error for the parser. build_queries.sh treats it as
# "use the default profile" — that decision belongs there, not here.
out=$(parse_preferences "$tmpdir/nope.md" 2>&1); rc=$?
[ "$rc" = "10" ] || fail "missing file: want exit 10, got $rc ($out)"

# 11. Determinism: same file, two runs, byte-identical output.
A=$(parse_preferences "$tmpdir/basic.md")
B=$(parse_preferences "$tmpdir/basic.md")
[ "$A" = "$B" ] || fail "parse is not deterministic"

echo "OK test_parse_preferences.sh"
