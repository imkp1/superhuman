#!/usr/bin/env bash
# build_queries.sh: preferences -> GitHub search queries.
#
# Every assertion here guards a failure that GitHub reports as success. A second
# `topic:` silently intersects; a typo'd qualifier key becomes free text; a
# parenthesized OR returns total_count: 0. All of them exit 0 and read as a thin
# week for open source. The API will never tell you — these tests are the only
# thing that will.
set -uo pipefail
CLAUDE_PLUGIN_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
export CLAUDE_PLUGIN_ROOT
BUILD="$CLAUDE_PLUGIN_ROOT/scripts/repo-finder/build_queries.sh"
GOLDEN="$CLAUDE_PLUGIN_ROOT/tests/fixtures/default_queries.txt"

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

# Fake HOME: the default path writes the once-per-install nudge flag into
# ~/.superhuman/global/last_version.json, and a test must never touch the real one.
HOME="$tmpdir/home"; export HOME
mkdir -p "$HOME"

fail() { echo "FAIL: $*"; exit 1; }

write() { cat > "$tmpdir/$1.md"; }
run()   { bash "$BUILD" --file "$tmpdir/$1.md" --no-nudge 2>/dev/null; }
count() { run "$1" | grep -c . ; }

# Never `run x | grep -q`: under `set -o pipefail`, grep -q exits on the first
# match, SIGPIPEs the builder, and the pipeline reports 141 — a MATCH reads as a
# failure. Match against a captured string instead.
has()    { grep -q "$2" <<EOF
$1
EOF
}
hasnt()  { has "$1" "$2" && return 1; return 0; }

# ---------------------------------------------------------------------------
# The strict shape, exercised only by a configured profile.
# ---------------------------------------------------------------------------

# 2. A Go+backend profile emits Go, and no python anywhere.
write go_backend <<'EOF'
## Filters
languages: go
topics: backend
stars: 2000
EOF
OUT=$(run go_backend)
[ "$OUT" = "language:go topic:backend stars:>2000 archived:false" ] \
  || fail "go+backend: got '$OUT'"
hasnt "$OUT" 'language:python' || fail "python leaked into a Go profile"

# 3. THE test. Exactly one topic: per query. Two topic: qualifiers on one line
# silently AND — repos tagged with EVERY topic, often none, exit 0, no error.
# go+rust × backend+infra must emit 2 queries (one per topic, both languages in
# each), never 4, never 1-with-both-topics.
write cross <<'EOF'
## Filters
languages: go, rust
topics: backend, infrastructure
stars: 2000
EOF
[ "$(count cross)" = "2" ] || fail "want 2 queries (one per topic), got $(count cross)"
run cross > "$tmpdir/cross.txt"
while IFS= read -r q; do
  n=$(printf '%s\n' "$q" | tr ' ' '\n' | grep -c '^topic:')
  [ "$n" -le 1 ] || fail "$n topic: qualifiers in one query: $q"
done < "$tmpdir/cross.txt"

# 4. Query count == |topics|. Adding a language must add ZERO queries — if the
# count scales with language count, the OR collapse was lost and the cross
# product is back.
write cross3 <<'EOF'
## Filters
languages: go, rust, python
topics: backend, infrastructure
stars: 2000
EOF
[ "$(count cross3)" = "2" ] \
  || fail "a third language added queries: $(count cross3) (languages are free)"

# 5. Every query carries the full language union.
run cross3 > "$tmpdir/cross3.txt"
while IFS= read -r q; do
  for l in go rust python; do
    case "$q" in *"language:$l"*) ;; *) fail "language:$l missing from: $q" ;; esac
  done
done < "$tmpdir/cross3.txt"

# 9c. `any` emits a TOPIC-LESS query, never a literal topic:any (GitHub has a
# real `any` topic; topics: any will never mean it).
write anytopic <<'EOF'
## Filters
languages: go
topics: backend, any
stars: 2000
EOF
[ "$(count anytopic)" = "2" ] || fail "any: want 2 queries, got $(count anytopic)"
A=$(run anytopic)
has "$A" '^language:go stars:>2000 archived:false$' \
  || fail "any must emit a query with no topic: qualifier"
hasnt "$A" 'topic:any' || fail "literal topic:any emitted"

# 9b. An omitted topics: line IS topics: any — one mechanism, not two rules.
write omitted <<'EOF'
## Filters
languages: go
stars: 2000
EOF
write explicit <<'EOF'
## Filters
languages: go
topics: any
stars: 2000
EOF
[ "$(run omitted)" = "$(run explicit)" ] \
  || fail "omitted topics: must be byte-identical to 'topics: any'"
[ "$(count omitted)" = "1" ] || fail "omitted topics: want 1 query, got $(count omitted)"

# 9d. A per-entry floor overrides the global floor, for its own entry and no other.
write floors <<'EOF'
## Filters
languages: go
topics: backend, llm:5000
stars: 20000
EOF
F=$(run floors)
has "$F" '^language:go topic:backend stars:>20000 archived:false$' \
  || fail "global floor not applied to backend"
has "$F" '^language:go topic:llm stars:>5000 archived:false$' \
  || fail "per-entry floor not applied to llm"

# 9e. No LLM in the scan path. A ## Notes sentence must not alter a single query —
# that compile happens in /preferences, at authoring, with a human confirming.
write prose <<'EOF'
## Filters
languages: go
topics: backend
stars: 2000

## Notes
I need llm repos having >5k stars, and rust too.
EOF
[ "$(run prose)" = "$(run go_backend)" ] \
  || fail "a Notes sentence changed the emitted queries"

# ---------------------------------------------------------------------------
# Invariants that hold for every emitted query, on every profile.
# ---------------------------------------------------------------------------
ALL="$tmpdir/all.txt"
{ run cross3; run anytopic; run floors
  bash "$BUILD" --file "$tmpdir/none.md" --no-nudge 2>/dev/null; } > "$ALL"

# 6. Qualifier-key allowlist. A typo'd key (langauge:go) is parsed as free text
# and returns total_count: 0 with exit 0 — an allowlist is the only thing that
# catches this class.
while IFS= read -r q; do
  for tok in $q; do
    case "${tok%%:*}" in
      language|topic|stars|archived) ;;
      *) fail "qualifier key outside the allowlist: '$tok' in: $q" ;;
    esac
  done
done < "$ALL"

# 7. No catch-all: every query carries a language: or a topic:.
while IFS= read -r q; do
  case "$q" in
    *language:*|*topic:*) ;;
    *) fail "catch-all query (no language:, no topic:): $q" ;;
  esac
done < "$ALL"

# 8. No boolean operators. Repeated `language:` is NOT an operator — it is the
# sanctioned union mechanism and must not trip this check.
grep -qE ' (OR|AND) |[()]' "$ALL" && fail "boolean operator or paren in an emitted query"

# 9f. No negation. Exclusion was considered and rejected; this pins it.
grep -qE '\-(language|topic):' "$ALL" && fail "negated qualifier emitted"

# 14. Stars are floor-only. No ceiling exists anywhere: no `..`, no `stars:<`.
grep -qE '\.\.|stars:<' "$ALL" && fail "star ceiling emitted"
grep -q 'stars:>' "$ALL" || fail "no star floor emitted at all"

# ---------------------------------------------------------------------------
# The default path is a pure refactor.
# ---------------------------------------------------------------------------

# 9. No preferences file => DEFAULT_PROFILE emits byte-identical queries to the
# five the agent carried before this change. /contribute on a fresh machine
# cannot regress, because the queries are literally the same bytes.
bash "$BUILD" --file "$tmpdir/none.md" --no-nudge > "$tmpdir/default.txt" 2>/dev/null
diff -u "$GOLDEN" "$tmpdir/default.txt" || fail "default queries drifted from the golden list"

# 9a. The default keeps UNION semantics: no default query carries both a
# language: and a topic:. If one does, the strict shape has leaked into the
# default path and fresh-machine behavior has silently changed.
while IFS= read -r q; do
  case "$q" in
    *language:*) case "$q" in *topic:*) fail "strict shape leaked into the default: $q" ;; esac ;;
  esac
done < "$tmpdir/default.txt"

# 10. The nudge fires once per install, not every run. A nag you see ten times is
# a nag you stop reading.
rm -rf "$HOME/.superhuman"
N1=$(bash "$BUILD" --file "$tmpdir/none.md" 2>&1 >/dev/null)
N2=$(bash "$BUILD" --file "$tmpdir/none.md" 2>&1 >/dev/null)
case "$N1" in *"/preferences"*) ;; *) fail "first default run did not nudge" ;; esac
[ -z "$N2" ] || fail "the nudge re-fired on a second run: $N2"
[ "$(jq -r '.preferences_nudged' "$HOME/.superhuman/global/last_version.json")" = "true" ] \
  || fail "nudge flag not persisted to last_version.json"

# The nudge must never contaminate the query list: it goes to stderr.
bash "$BUILD" --file "$tmpdir/none.md" 2>/dev/null | diff -q - "$GOLDEN" >/dev/null \
  || fail "nudge text leaked into stdout"

# ---------------------------------------------------------------------------
# Malformed preferences abort. They never degrade to an unfiltered scan.
# ---------------------------------------------------------------------------
write bad <<'EOF'
## Filters
langauges: go
EOF
bash "$BUILD" --file "$tmpdir/bad.md" --no-nudge >/dev/null 2>&1
rc=$?
[ "$rc" = "10" ] || fail "malformed preferences must exit 10, got $rc (never fall back to defaults)"

# ---------------------------------------------------------------------------
# A file with no ## Filters CONTENT is "default filters + advisory notes", NOT a
# catch-all to reject. It must fall back to DEFAULT_PROFILE, never abort with the
# misleading 'topics: any with no languages' error the user never wrote. The
# malformed-abort test above guards the other direction: a Filters block WITH a
# bad line still exits 10, so the fallback can never swallow a real typo.
# ---------------------------------------------------------------------------

# 12. Notes-only file (no ## Filters block at all) => DEFAULT_PROFILE, exit 0.
write notes_only <<'EOF'
## Notes
Prefer small, focused libraries. I'd rather fix bugs than add features.
EOF
run notes_only > "$tmpdir/notes_only.txt" \
  || fail "notes-only preferences.md aborted the scan instead of using defaults"
diff -u "$GOLDEN" "$tmpdir/notes_only.txt" \
  || fail "notes-only file did not fall back to the default profile"

# 12a. An empty ## Filters block (header, no filter lines) is also 'nothing
# specified' => DEFAULT_PROFILE, not a catch-all abort.
write empty_filters <<'EOF'
## Filters

## Notes
just some guidance
EOF
run empty_filters > "$tmpdir/empty_filters.txt" \
  || fail "empty ## Filters block aborted the scan instead of using defaults"
diff -u "$GOLDEN" "$tmpdir/empty_filters.txt" \
  || fail "empty ## Filters block did not fall back to the default profile"

# 11. Determinism: same profile, two runs, byte-identical output.
[ "$(run cross3)" = "$(run cross3)" ] || fail "build is not deterministic"

echo "OK test_build_queries.sh"
