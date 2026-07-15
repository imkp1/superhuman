---
name: preferences
description: Set what /repo-finder searches for — languages, topics, star floor, and free-form notes. Writes ~/.superhuman/preferences.md. Usage — `/preferences` (the form) or `/preferences --show` (print the current file and the queries it compiles to).
---

You author `~/.superhuman/preferences.md`. It sits at the root of `~/.superhuman/`
rather than under `global/` because it is not state — it is *input*, the file that
tells the plugin what the user wants. No agent ever writes it.

`/repo-finder` reads it on every run. Until it exists, the scan uses a default
profile: ai-ml, java, python and devtools at **>20K stars**, with `llm` at
**>5K** (LLM repos are younger; a 20K floor erases the category).

## The file

```markdown
# My superhuman preferences

## Filters
languages: go, rust
topics: backend, infrastructure, llm:5000, any
stars: 2000

## Notes
Prefer small focused libraries over sprawling frameworks.
I'd rather fix bugs than add features — feature work invites bikeshedding.
Nothing that needs a GPU to run the test suite.
```

The two halves promise different things, and being explicit about which one binds
is the whole point:

- **`## Filters` is mechanical.** Parsed by `scripts/lib/preferences.sh`, compiled
  1:1 into GitHub search qualifiers. "Only Go and Rust" means only Go and Rust.
- **`## Notes` is advisory.** No code can hard-filter on "focused rather than
  sprawling". The agent applies it at tie-breaks and issue selection, and it must
  disclose in the shortlist's `notes` field when it did. Prose is never allowed to
  move a numeric score.

Treating prose as if it were a filter is exactly how the old version ended up
ignoring its own `stars:>20000`.

## Syntax

| Line | Meaning |
|---|---|
| `languages: go, rust` | Language ∈ {go, rust}. **Languages are free** — they OR inside one query, so adding one costs zero queries. |
| `topics: backend, llm:5000` | **One query per topic.** `topic[:min_stars]` — a per-entry floor overrides the global one for that topic only. |
| `topics: … , any` | `any` is **reserved**: it compiles to a query with *no* `topic:` qualifier, for repos carrying none of your tags. It never means GitHub's real `any` topic. |
| *(no `topics:` line)* | Exactly `topics: any`. |
| `stars: 2000` | A **floor**. There is no ceiling — no ranges, no maximum. |

**Why no star ceiling.** The only argument for one is "mega-repos don't merge
outsider PRs", and `repo-finder` already measures that per repo from real data
(median response time, median merge time, external-merge ratio, pre-approval PR
templates). A ceiling is a guess about those measurements; the scorer has the
answer. Worse, it fails asymmetrically: `ollama` (~176K), `ragflow` (~85K) and
`netdata` (~80K) all sit above any plausible cap, so a ceiling silently deletes
the category the default profile exists to find. A range in the file is a **loud
error**, not a quietly honored cap.

## Workflow

### Step 1: `--show`

If `$ARGUMENTS` is `--show`, print the current file and the queries it compiles
to, then stop:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/lib/usage_event.sh" --command preferences >/dev/null 2>&1 & disown 2>/dev/null || true

PREFS="$HOME/.superhuman/preferences.md"
if [ ! -f "$PREFS" ]; then
  echo "No preferences yet — /repo-finder is using the default profile."
else
  cat "$PREFS"
fi
echo
echo "Your next /repo-finder will search:"
"${CLAUDE_PLUGIN_ROOT}/scripts/repo-finder/build_queries.sh" --no-nudge | sed 's/^/  q=/'
```

### Step 2: Ask four things

1. **Languages** — free text, comma-separated. Empty means any language.
2. **Topics** — offer these well-populated GitHub topics as a multi-select, and
   accept free text for anything else: `backend`, `infrastructure`, `devops`,
   `cli`, `database`, `security`, `frontend`, `machine-learning`. The list is a
   convenience, not a gate — **any GitHub topic is valid**. Mention `any` as the
   option for "…plus untagged repos I might like".
3. **Star floor** — default `2000`. Say why: smaller repos merge outsider PRs
   faster. Offer **no** ceiling.
4. **Anything else, in your own words** — free text, lands in `## Notes`.

### Step 3: Count the compiled queries live

A typo'd topic is not an error at GitHub — it is a filter that silently matches
nothing, and the scan reads as a thin week for open source.

**Count the query the scan will actually run, not the bare topic.** Two failures
hide behind a bare `topic:` check, and both look like a healthy filter:

- **A typo other people also made.** `topic:bakcend` matches 26 real repos — humans
  misspell their own topics — so any `total_count > 0` test passes it, and the scan
  still returns nothing once the *other* qualifiers apply.
- **A correct topic that is empty in context.** `topic:backend` has ~42K repos, but
  `language:go language:python topic:backend stars:>20000` matches **2**. Nothing is
  misspelled; the profile is too narrow to rank.

Only the compiled query answers either question, and it costs the same one call per
topic.

```bash
# Compile the candidate profile, then count what it emits. Call build_queries.sh
# rather than re-deriving the queries here: it is the single compiler, and a second
# one would drift from the scan this check is meant to predict.
# mktemp, not $$-predictable names: `>` onto a guessable path in a world-writable
# /tmp is open to stale-file reuse and symlink redirection. Both temps live and die
# inside this block, so an EXIT trap is the right cleanup here.
CHECK=$(mktemp "${TMPDIR:-/tmp}/superhuman-prefs-check.XXXXXX") || { echo "mktemp failed"; exit 1; }
CHECKQ=$(mktemp "${TMPDIR:-/tmp}/superhuman-prefs-checkq.XXXXXX") || { rm -f "$CHECK"; echo "mktemp failed"; exit 1; }
trap 'rm -f "$CHECK" "$CHECKQ"' EXIT
{
  echo "## Filters"
  [ -n "$LANGUAGES" ] && echo "languages: $LANGUAGES"
  [ -n "$TOPICS" ]    && echo "topics: $TOPICS"
  echo "stars: $STARS"
} > "$CHECK"

# A malformed profile exits 10 here — before anything reaches disk.
"${CLAUDE_PLUGIN_ROOT}/scripts/repo-finder/build_queries.sh" --file "$CHECK" --no-nudge \
  > "$CHECKQ" || { echo "Fix the filters above and try again."; exit 10; }

while IFS= read -r q; do
  [ -n "$q" ] || continue
  # total_count, not the items array: a MALFORMED query also returns an empty
  # array, so counting rows cannot tell a typo from a genuinely empty result.
  n=$(gh api -X GET search/repositories -f q="$q" -f per_page=1 --jq '.total_count')
  printf '  %s\n    -> %s repos\n' "$q" "${n:-0}"
  if [ "${n:-0}" -eq 0 ]; then
    echo "    WARNING: matches NOTHING. Check the topic for a typo, or lower the star floor."
  elif [ "${n:-0}" -lt 10 ]; then
    echo "    WARNING: only ${n} repos — too few to rank. Lower the star floor, or drop a language."
  fi
done < "$CHECKQ"
```

`any` needs no special handling: it is reserved, and `build_queries.sh` already
compiles it to a query with no `topic:` qualifier — so what gets counted is that
query, which is the thing that matters.

This lives here and nowhere else. The unit suite is network-free by design, so a
live check belongs in the interactive command, which always has a network.

**Cap topics at 20.** Query count *is* topic count, and GitHub's search API allows
30 requests/minute. Do not cap languages — they cost nothing.

### Step 4: Compile prose, and show the compile

The user may answer in a sentence. **You may compile a sentence into `## Filters`
— here, at authoring, with the user confirming.** Show them the result before you
write it:

```text
You said: "I need llm repos having >5k stars, and Go backend stuff"

Writing to ~/.superhuman/preferences.md:
  languages: go
  topics: llm:5000, backend
  stars: 2000

Your next /repo-finder will search:
  q='language:go topic:llm     stars:>5000 archived:false'
  q='language:go topic:backend stars:>2000 archived:false'
  2 queries — one per topic.                              [y/n]
```

Anything that cannot become a qualifier — *"prefer small focused libraries"*,
*"rather fix bugs than add features"* — goes to `## Notes` and stays advisory.

**The compile happens once, at authoring.** What lands on disk is mechanical, and
`build_queries.sh` never sees a sentence: an LLM in the scan path costs
determinism (same file, same queries, every run), testability (CI is network-free,
so a prose-driven generator cannot be tested by the gate that protects it), and
fail-loudness (a misparsed sentence scans confidently wrong with exit 0).

### Step 5: Write, then echo the queries

Atomic temp-rename, same as every other writer:

```bash
PREFS="$HOME/.superhuman/preferences.md"
mkdir -p "$HOME/.superhuman"
# mktemp in the destination dir, not a $$-predictable sibling: keeps the rename
# atomic (same filesystem) while closing the stale-file/symlink window.
TMP=$(mktemp "$PREFS.tmp.XXXXXX") || { echo "mktemp failed"; exit 1; }
cat > "$TMP" <<EOF
# My superhuman preferences

## Filters
languages: $LANGUAGES
topics: $TOPICS
stars: $STARS

## Notes
$NOTES
EOF

# Never leave a file the parser rejects. Round-trip it before the rename.
source "${CLAUDE_PLUGIN_ROOT}/scripts/lib/preferences.sh"
parse_preferences "$TMP" >/dev/null \
  || { echo "FATAL: refusing to write preferences the parser rejects" >&2; rm -f "$TMP"; exit 10; }
mv "$TMP" "$PREFS"

echo "Your next /repo-finder will search:"
"${CLAUDE_PLUGIN_ROOT}/scripts/repo-finder/build_queries.sh" --no-nudge | sed 's/^/  q=/'
```

Echoing the compiled queries is not decoration: it makes the filter
**non-opaque**. Ask for Go, see `language:python`, catch it in ten seconds instead
of three scans later. It also makes the AND/OR asymmetry visible — two `topic:`
qualifiers on one line is a bug the user can spot themselves.

## Rules

- **Never write a preferences file the parser rejects.** Round-trip through
  `parse_preferences` before the rename.
- **`stars:` is a floor.** Never offer a ceiling, never write a range.
- **Filters are always hard.** No `strict` flag, no per-axis softening — soft
  nuance lives in `## Notes`, which is where it can be honest about being soft.
- **`any` is reserved** and compiles to the absence of a `topic:` qualifier. Say
  so when the user picks it.
- **Cap topics at 20; never cap languages.**
- **Never infer preferences from the local filesystem.** A repo finder that
  rummages through `~/projects` looking for `go.mod` is not what anyone expects it
  to do, and this plugin ships to other people.
- **macOS bash 3.2 safe.** No bash 4 features.
