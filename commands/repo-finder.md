---
name: repo-finder
description: Refresh repo-shortlist.json with up to N candidate repos. Wraps the repo-finder agent. Usage — `/repo-finder` (default N=10), `/repo-finder 25` (request 25, capped at 25), or `/repo-finder 10 --lang rust --topic cli` (override this run's filters only).
---

You are a thin wrapper around the `repo-finder` agent. You validate
`$ARGUMENTS`, dispatch the agent, then render the refreshed shortlist on
return. The agent does the discovery — searches GitHub, scores repos
against the rubric, applies the reputation gate, writes
`~/.superhuman/global/repo-shortlist.json`. This command exists so the
shortlist refresh is invokable directly from the REPL without remembering
the agent name.

## Workflow

### Step 1: Resolve arguments

```bash
# Best-effort adoption telemetry (opt-out). Backgrounded + swallowed so it can
# never block or fail the command. See scripts/lib/usage_event.sh, TELEMETRY.md.
"${CLAUDE_PLUGIN_ROOT}/scripts/lib/usage_event.sh" --command repo-finder >/dev/null 2>&1 & disown 2>/dev/null || true

N=10
LANGS="" TOPICS="" MIN_STARS=""

# NOTHING IN THIS FILE MAY READ $1..$9. They are slash-command template
# placeholders: the harness substitutes them at load time, before bash runs. A
# `case "$1"` argv parser therefore arrives as `case ""`, every token falls
# through to the usage arm, and `/repo-finder 5` exits 1 — the shell never sees
# the positional parameter that was written here. Parse the token stream with a
# pending-flag state variable and named locals instead; read no positional.
#
# Tokens are split on space/tab by hand because zsh — the macOS default, and the
# shell this block runs in — does not word-split unquoted expansions: an
# unquoted $ARGUMENTS arrives glued into one argument. Splitting explicitly also
# subsumes what `set -f` guarded: no token is left unquoted, so `--topic c*`
# cannot glob against the cwd.
#
# A `while ... done <<EOF` redirect does not fork a subshell, so these
# assignments survive the loop.
PENDING="" ERR=""
while IFS= read -r tok; do
  [ -n "$tok" ] || continue

  if [ -n "$PENDING" ]; then
    case "$PENDING" in
      lang)      LANGS="${LANGS:+$LANGS, }$tok" ;;
      topic)     TOPICS="${TOPICS:+$TOPICS, }$tok" ;;
      min-stars) MIN_STARS="$tok" ;;
    esac
    PENDING=""
    continue
  fi

  case "$tok" in
    --lang|--language) PENDING=lang ;;
    --topic)           PENDING=topic ;;
    --min-stars)       PENDING=min-stars ;;
    --max-stars)
      # Never had one, never will. main's queries are all lower-bound only, and a
      # ceiling deletes exactly the repos the responsiveness scorer exists to
      # judge (ollama ~176K, ragflow ~85K) with no error. Reject it loudly rather
      # than accept a flag that quietly narrows the search.
      ERR=ceiling; break ;;
    [0-9]*)            N="$tok" ;;
    *)                 ERR=usage;   break ;;
  esac
done <<EOF
$(printf '%s' "$ARGUMENTS" | tr ' \t' '\n\n')
EOF

# A trailing flag with no value is a usage error, not a silently dropped flag.
[ -n "$PENDING" ] && { echo "--$PENDING needs a value"; ERR=usage; }

case "$ERR" in
  ceiling)
    echo "There is no star ceiling: stars is a floor. See /preferences."
    exit 1 ;;
  usage)
    echo "Usage: /repo-finder [N] [--lang X] [--topic Y] [--min-stars Z]"
    echo "  N: positive integer, max 25. Overrides apply to this run only."
    exit 1 ;;
esac

case "$N" in ''|*[!0-9]*) echo "N must be a positive integer"; exit 1 ;; esac
case "$MIN_STARS" in *[!0-9]*) echo "--min-stars must be a positive integer"; exit 1 ;; esac
[ "$N" -gt 25 ] && N=25
[ "$N" -lt 1 ]  && N=1
```

The cap of 25 is deliberate: the shortlist is meant to be human-scannable
in the dashboard. Beyond 25 the per-repo scoring cost outpaces the value.

**Overrides apply to this run only.** They compile to a throwaway preferences
file and are handed to the agent through `SUPERHUMAN_PREFS`; the saved
`~/.superhuman/preferences.md` is never touched. `/repo-finder 5 --lang rust` on a
Go profile searches Rust once, and the next bare `/repo-finder` is Go again.

An override **replaces** the axis it names — `--lang rust` means Rust, not
"Go plus Rust". Unnamed axes fall back to the saved profile, or to its defaults
when there is none.

```bash
PREFS_ARG=""
if [ -n "$LANGS$TOPICS$MIN_STARS" ]; then
  SAVED="$HOME/.superhuman/preferences.md"
  # mktemp, not a $$-predictable name: `>` onto a guessable path in a world-writable
  # /tmp is open to stale-file reuse and symlink redirection. The file must outlive
  # this block (the agent reads it in Step 2), so it is removed explicitly on the
  # error path below and after the agent returns — not via an EXIT trap that would
  # fire the moment this block ends.
  OVERRIDE=$(mktemp "${TMPDIR:-/tmp}/superhuman-prefs.XXXXXX") || { echo "mktemp failed"; exit 1; }

  # If any axis is inherited from the saved profile, that profile must itself be
  # valid. A malformed saved line (e.g. `langauges: go`) is caught on the normal
  # /repo-finder path but would be silently dropped by the key-specific extraction
  # below, letting an override bypass the fail-loud contract. Validate with the
  # same compiler the normal path uses — but only when something is actually
  # inherited (a full --lang/--topic/--min-stars override never reads it).
  if [ -f "$SAVED" ] && { [ -z "$LANGS" ] || [ -z "$TOPICS" ] || [ -z "$MIN_STARS" ]; } \
     && ! "${CLAUDE_PLUGIN_ROOT}/scripts/repo-finder/build_queries.sh" --file "$SAVED" --no-nudge >/dev/null 2>&1; then
    echo "Saved ~/.superhuman/preferences.md is malformed; fix it or run /preferences (an override inherits the axes it doesn't name)."
    rm -f "$OVERRIDE"; exit 1
  fi

  # Inherit each unnamed axis from the saved profile, so --lang rust on a
  # backend-topics profile still searches backend. Read only the `## Filters` block:
  # a `## Notes` line that happens to begin `languages:`/`topics:`/`stars:` (copied
  # prose) must never be mistaken for a hard filter.
  FILTERS=""
  # Detect the block with the SAME matcher scripts/lib/preferences.sh uses
  # (case-insensitive via tolower, spacing-tolerant). A divergent reader silently
  # fails to inherit saved axes on a '## filters'/'## FILTERS' file and searches
  # with defaults instead — the silent-wrong-result this whole feature guards against.
  [ -f "$SAVED" ] && FILTERS=$(awk '
    /^##[ \t]+/ { f = (tolower($0) ~ /^##[ \t]*filters[ \t]*$/); next }
    f
  ' "$SAVED")
  if [ -z "$LANGS" ]; then
    LANGS=$(printf '%s\n' "$FILTERS" | sed -n 's/^[[:space:]]*languages:[[:space:]]*//p' | head -1)
  fi
  if [ -z "$TOPICS" ]; then
    TOPICS=$(printf '%s\n' "$FILTERS" | sed -n 's/^[[:space:]]*topics:[[:space:]]*//p' | head -1)
  fi
  if [ -z "$MIN_STARS" ]; then
    MIN_STARS=$(printf '%s\n' "$FILTERS" | sed -n 's/^[[:space:]]*stars:[[:space:]]*//p' | head -1)
  fi
  [ -n "$MIN_STARS" ] || MIN_STARS=2000

  {
    echo "# Per-run override — not saved."
    echo
    echo "## Filters"
    [ -n "$LANGS" ]  && echo "languages: $LANGS"
    [ -n "$TOPICS" ] && echo "topics: $TOPICS"
    echo "stars: $MIN_STARS"
  } > "$OVERRIDE"

  # Fail before the scan, not during it: a malformed override must not silently
  # fall through to the saved profile or the default one.
  "${CLAUDE_PLUGIN_ROOT}/scripts/repo-finder/build_queries.sh" --file "$OVERRIDE" --no-nudge \
    | sed 's/^/  q=/' \
    || { echo "Invalid override."; rm -f "$OVERRIDE"; exit 1; }
  PREFS_ARG="$OVERRIDE"
fi
```

### Step 2: Dispatch the agent

Pass `SUPERHUMAN_PREFS` only when an override is in play — otherwise the agent
reads the saved profile, or falls back to the default one.

```text
Agent(
  subagent_type: "repo-finder",
  description: "refresh repo shortlist (N=<N>)",
  prompt: |
    N=<N>
    MODE=cli
    SUPERHUMAN_PREFS=<PREFS_ARG, if set>
)
```

Delete the override file once the agent returns: `rm -f "$OVERRIDE"`.

### Step 3: Render the new shortlist

```bash
SHORTLIST="$HOME/.superhuman/global/repo-shortlist.json"
if [ ! -f "$SHORTLIST" ]; then
  echo "repo-finder agent did not write $SHORTLIST. Check its output."
  exit 1
fi

echo "Top $N candidates:"

# Coverage line: make a partial scan visible here, not only in the agent's reply.
# `scored` < `survivors` means repos were never evaluated — the list is short
# because the scan stopped, not because the field is thin. Absent on older
# shortlists written before coverage existed, so print only when present.
jq -e '.coverage' "$SHORTLIST" >/dev/null 2>&1 && \
  jq -r '.coverage | "  coverage: scored \(.scored // "?")/\(.survivors // "?") survivors, returned \(.returned // "?") of \(.candidates // "?") candidates"' "$SHORTLIST"

# No awk here, for the same reason the parser above reads no positional: awk's
# field refs are spelled $1/$2/$3, and the harness eats them exactly as it eats
# a shell positional. `printf "%-6s %-32s %s\n",$1,$2,$3` reaches bash as
# `printf "%-6s %-32s %s\n",,,` — an awk syntax error, or worse, three blank
# columns. Format with shell printf over a jq @tsv stream instead.
printf "%-6s %-32s %s\n" score repo notes
jq -r '.repos[] | [(.scores.final|tostring), .repo, (.notes // "")] | @tsv' "$SHORTLIST" \
  | head -"$N" \
  | while IFS="$(printf '\t')" read -r f_score f_repo f_notes; do
      printf "%-6s %-32s %s\n" "$f_score" "$f_repo" "$f_notes"
    done
```

## Rules

- **Cap at N=25.** Higher values waste GitHub search quota and produce a
  list humans cannot scan. The agent itself enforces this internally; the
  cap here is defense in depth.
- **Reputation gate is the agent's job.** Both the agent (during
  candidate scoring) and `opensource-contributor` Phase 0 (at dispatch
  time) re-check blocklist + cooldown + active-lock. This wrapper does
  not gate.
- **`$ARGUMENTS` is optional.** Empty defaults to N=10 and the saved
  preferences (or the default profile when none exist). Anything that is
  not a positive integer or a known override flag is rejected with a
  usage line.
- **Overrides never persist.** `--lang` / `--topic` / `--min-stars` shape
  one run. Only `/preferences` writes `~/.superhuman/preferences.md`.
- **There is no `--max-stars`.** `stars` is a floor. A ceiling is a guess
  about what the responsiveness scorer already measures per repo, and it
  silently deletes the biggest, most active repos rather than letting the
  scorer judge them.
- **macOS bash 3.2 safe.** No bash 4 features.
