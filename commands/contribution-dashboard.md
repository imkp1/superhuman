---
name: contribution-dashboard
description: Read-only dashboard for the opensource-contributor state. Shows active run, score history, plateaued dimensions, iteration cap, recent merge outcomes, and active reputation blocks/cooldowns. Usage — `/contribution-dashboard` (all repos) or `/contribution-dashboard <owner>/<repo>` (single repo).
---

You are a read-only dashboard. You never write to state files. You never
dispatch other agents. You read `~/.superhuman/repos/` and
`~/.superhuman/global/`, summarize the current contribution (if any),
recent merge outcomes, and the reputation gate state, and print a compact
status report.

## Arguments

The user may pass a single `owner/repo` slug (e.g.
`/contribution-dashboard apache/airflow`). In the workflow below the slug
is available as `$ARGUMENTS`. If empty, show all repos.

## Workflow

### Step 1: Resolve target scope

```bash
# Best-effort adoption telemetry (opt-out). Backgrounded + swallowed so it can
# never block or fail the command. See scripts/lib/usage_event.sh, TELEMETRY.md.
"${CLAUDE_PLUGIN_ROOT}/scripts/lib/usage_event.sh" --command contribution-dashboard >/dev/null 2>&1 & disown 2>/dev/null || true

ROOT="$HOME/.superhuman/repos"
GLOBAL_DIR="$HOME/.superhuman/global"

if [ ! -d "$ROOT" ]; then
  echo "No contribution state yet. Run /opensource-contributor first."
  exit 0
fi

# Stage the slash-command arg into a plain shell var. The framework
# substitutes $ARGUMENTS before Claude sees this block; at bash exec
# time we work with ARG.
ARG="$ARGUMENTS"

TARGET_DIRS=()
if [ -n "$ARG" ]; then
  SLUG="${ARG/\//-}"
  TDIR="$ROOT/$SLUG"
  if [ ! -d "$TDIR" ]; then
    echo "No state for $ARG"; exit 0
  fi
  TARGET_DIRS+=("$TDIR")
else
  # Portable replacement for bash-4 `mapfile` (macOS ships bash 3.2).
  while IFS= read -r d; do
    TARGET_DIRS+=("$d")
  done < <(find "$ROOT" -mindepth 1 -maxdepth 1 -type d | sort)
fi
```

### Step 2: For each repo, read current_contribution.json

```bash
for dir in "${TARGET_DIRS[@]}"; do
  CC="$dir/current_contribution.json"
  [ -f "$CC" ] || { echo "(no current_contribution.json in $(basename "$dir"))"; continue; }

  REPO=$(jq -r '.repo // "?"' "$CC" 2>/dev/null) \
    || { echo "(state file malformed: $CC)"; continue; }
  ISSUE=$(jq -r '.issue_number // "—"' "$CC")
  BRANCH=$(jq -r '.branch // "—"' "$CC")
  ITER=$(jq -r '.iteration // 0' "$CC")
  MAX=$(jq -r '.max_iterations // "?"' "$CC")
  LOCK=$(jq -r '.lock_holder // "released"' "$CC")
  PR=$(jq -r '.pr_url // "(no PR yet)"' "$CC")
  LAST_SCORE=$(jq -r '.scores[-1].final // "—"' "$CC")
  PLATEAU=$(jq -r '.scores[-1].plateaued // [] | join(",")' "$CC")
  SCORES=$(jq -r '.scores[] | "  iter \(.iteration): \(.final)%"' "$CC")
done
```

### Step 3: Read repo_profile.json for context

```bash
PROFILE="$dir/repo_profile.json"
LANG=$(jq -r '.language // "?"' "$PROFILE" 2>/dev/null || echo "?")
TR=$(jq -r '.test_runner // "?"' "$PROFILE" 2>/dev/null || echo "?")
```

### Step 3.5: Learning substrate (rule cards + dossier)

Per-repo view of what the `lesson-distiller` has learned for this repo. Both
files may be absent on a repo not yet seeded or curated — the `[ -f ]` guards
leave every count at 0 so the panel renders cleanly with "no rule cards yet".

```bash
LESSONS="$dir/lessons.jsonl"
DOSSIER_META="$dir/dossier_meta.json"

# lessons.jsonl is one rule card per line (owner: lesson-distiller).
L_TOTAL=0; L_ACTIVE=0; L_ENF=0; L_DET=0; L_SEM=0; L_DEMOTED=0
if [ -f "$LESSONS" ]; then
  L_TOTAL=$(jq -s 'length' "$LESSONS" 2>/dev/null || echo 0)
  L_ACTIVE=$(jq -s '[.[]|select(.status=="active")]|length' "$LESSONS" 2>/dev/null || echo 0)
  L_ENF=$(jq -s '[.[]|select(.status=="active" and (.confidence//0)>=0.75 and (.scope=="repo" or .scope=="global"))]|length' "$LESSONS" 2>/dev/null || echo 0)
  L_DET=$(jq -s '[.[]|select(.kind=="deterministic")]|length' "$LESSONS" 2>/dev/null || echo 0)
  L_SEM=$(jq -s '[.[]|select(.kind=="semantic")]|length' "$LESSONS" 2>/dev/null || echo 0)
  L_DEMOTED=$(jq -s '[.[]|select(.status=="demoted")]|length' "$LESSONS" 2>/dev/null || echo 0)
fi

DOSSIER_STATE="not seeded"
if [ -f "$DOSSIER_META" ]; then
  DH=$(jq -r '.head_sha // "" | .[0:7]' "$DOSSIER_META" 2>/dev/null)
  DA=$(jq -r '.authored_at // "?"' "$DOSSIER_META" 2>/dev/null)
  [ -n "$DH" ] && DOSSIER_STATE="seeded @ $DH ($DA)"
fi
```

Never call `jq` on a path you have not `[ -f ]`-guarded: a missing file makes
`jq -s` emit a spurious `0` on stdout AND exit non-zero, so `|| echo 0` would
double-count. The guard is the missing-file handler; `|| echo 0` only catches a
malformed file.

### Step 4: Reputation state (global)

```bash
NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
BLOCKLIST="$GLOBAL_DIR/repo_blocklist.json"
COOLDOWN="$GLOBAL_DIR/repo_cooldown.json"

ACTIVE_BLOCKS=""
if [ -f "$BLOCKLIST" ]; then
  ACTIVE_BLOCKS=$(jq -r --arg now "$NOW" \
    '.blocked[] | select(.expires_at == null or .expires_at > $now)
       | "  \(.repo) — \(.reason)\(if .expires_at then " (until " + .expires_at + ")" else " (permanent)" end)"' \
    "$BLOCKLIST" 2>/dev/null)
fi

ACTIVE_COOLDOWNS=""
if [ -f "$COOLDOWN" ]; then
  ACTIVE_COOLDOWNS=$(jq -r --arg now "$NOW" \
    '.cooldowns[] | select(.cooldown_until > $now)
       | "  \(.repo) — until \(.cooldown_until) (\(.triggering_outcomes | join(",")))"' \
    "$COOLDOWN" 2>/dev/null)
fi
```

### Step 5: Summarize recent global outcomes

```bash
GLOBAL="$GLOBAL_DIR/merge_outcomes.jsonl"
RECENT=""
if [ -f "$GLOBAL" ]; then
  RECENT=$(tail -5 "$GLOBAL" | jq -r \
    '"  \(.outcome)\t\(.repo) #\(.pr_url | capture("/pull/(?<n>[0-9]+)").n // "?")   (\(.iterations) iters)"' \
    2>/dev/null)
fi
```

### Step 5.5: Most recent loop run

`/contribute-loop` appends one JSON line per iteration to
`~/.superhuman/global/loop_runs.jsonl`. We surface the most recent
`loop_id` here so a user re-running the dashboard mid-loop can see
progress, and so a halted loop's last state is visible without grepping
files.

```bash
LOOP_LOG="$GLOBAL_DIR/loop_runs.jsonl"
LOOP_TABLE=""
LATEST_LOOP=""
if [ -f "$LOOP_LOG" ]; then
  # Tail-bound the scan so the dashboard stays fast even after months of
  # loops. 100 lines covers ~5 N=20 loops.
  LATEST_LOOP=$(tail -100 "$LOOP_LOG" | jq -r .loop_id 2>/dev/null \
    | sort -u | tail -1)
  if [ -n "$LATEST_LOOP" ]; then
    LOOP_TABLE=$(jq -r --arg loop "$LATEST_LOOP" \
      'select(.loop_id == $loop)
       | [.iter, .repo, .outcome, (.pr_url // "—")] | @tsv' "$LOOP_LOG" \
      | awk -F'\t' '{printf "  %-4s %-32s %-20s %s\n",$1,$2,$3,$4}')
  fi
fi
```

### Step 5.7: Learning substrate (global)

Cross-repo view: cards the `lesson-distiller` has promoted, and the regression
alarm log. `lessons_global.jsonl` holds promoted cards (`global-candidate` =
advisory, `global` = enforced everywhere); `lesson_regressions.jsonl` logs when
a known rule was shipped-violated or re-raised by a maintainer. Both may be
absent.

```bash
GLESSONS="$GLOBAL_DIR/lessons_global.jsonl"
G_TOTAL=0; G_CAND=0; G_PROMOTED=0
if [ -f "$GLESSONS" ]; then
  G_TOTAL=$(jq -s 'length' "$GLESSONS" 2>/dev/null || echo 0)
  G_CAND=$(jq -s '[.[]|select(.scope=="global-candidate")]|length' "$GLESSONS" 2>/dev/null || echo 0)
  G_PROMOTED=$(jq -s '[.[]|select(.scope=="global")]|length' "$GLESSONS" 2>/dev/null || echo 0)
fi

REGRESS="$GLOBAL_DIR/lesson_regressions.jsonl"
R_SHIP=0; R_RERAISE=0; R_RECENT=""
if [ -f "$REGRESS" ]; then
  R_SHIP=$(jq -s '[.[]|select(.kind=="shipped_violation")]|length' "$REGRESS" 2>/dev/null || echo 0)
  R_RERAISE=$(jq -s '[.[]|select(.kind=="maintainer_reraise")]|length' "$REGRESS" 2>/dev/null || echo 0)
  R_RECENT=$(tail -5 "$REGRESS" | jq -r '"\(.kind)\t\(.repo) \(.rule_id)"' 2>/dev/null \
    | awk -F'\t' '{printf "  %-20s %s\n",$1,$2}')
fi
```

### Step 6: Render

Per-repo block (width cap ≤100 cols):

```
═══ apache/airflow ═══
Issue: #65685      Branch: fix/65685-auth-role-public
Lock:  opensource-contributor
PR:    https://github.com/apache/airflow/pull/66010
Iter:  4 / 6       Last score: 92%
Plateaued: process, docs
Language: python   Tests: pytest
Learning: 12 cards (9 active, 5 enforced) — 4 det / 8 sem, 1 demoted
Dossier:  seeded @ a1b2c3d (2026-07-05T14:02:00Z)

Score history:
  iter 1: 68%
  iter 2: 79%
  iter 3: 85%
  iter 4: 92%
```

The `Learning`/`Dossier` lines render in every per-repo block (learning
persists across runs), including the "no active contribution" case below. Show
`Learning: (no rule cards yet)` when `L_TOTAL` is 0, and `Dossier: not seeded`
when `dossier_meta.json` is absent.

If no active contribution (lock released, no scores):

```
═══ apache/airflow ═══
(no active contribution — last run: merged, 4 iters)
Learning: 12 cards (9 active, 5 enforced) — 4 det / 8 sem, 1 demoted
Dossier:  seeded @ a1b2c3d (2026-07-05T14:02:00Z)
```

Global footer (always printed, even with no per-repo blocks):

```
═══ Reputation gate ═══
Blocklist (active):
  torvalds/linux — maintainer asked us to stop (permanent)
Cooldowns (active):
  psf/requests — until 2026-08-01T00:00:00Z (closed_no_merge,abandoned)

═══ Recent outcomes (last 5) ═══
  merged    apache/airflow #65685   (4 iters)
  merged    django/django #17812    (2 iters)
  abandoned psf/requests #6644      (5 iters)

═══ Learning substrate ═══
Global cards: 7 (2 candidates, 5 promoted)
Regressions:  2 shipped-violation, 1 maintainer-reraise
Recent:
  shipped_violation    apache/airflow airflow-tests-location
  maintainer_reraise   django/django  django-newsfragment

═══ Latest loop: loop-20260520T093000Z ═══
  iter repo                             outcome              pr
  1    apache/airflow                   merge_ready          https://github.com/apache/airflow/pull/66010
  2    django/django                    merged               https://github.com/django/django/pull/17812
  3    psf/requests                     suspicious_halt      —
```

If `loop_runs.jsonl` does not exist or has no entries, omit the latest-loop
section entirely — there is nothing to render and an empty heading would
clutter the output. The reputation and recent-outcomes sections still
print their `  (none)` placeholder when empty, because those are always
relevant; loop runs are only relevant when the user has actually run a
loop.

If a reputation section is empty, print `  (none)` rather than omitting
the heading — the user needs to see an empty list is empty, not missing.

## Rules

- **Read-only.** Never use `Write`, `Edit`, or any append. No `>>` redirects.
- **Tolerate missing files.** `repo_profile.json`, `repo_blocklist.json`,
  `repo_cooldown.json`, `merge_outcomes.jsonl`, `lessons.jsonl`,
  `dossier_meta.json`, `lessons_global.jsonl`, and `lesson_regressions.jsonl`
  may all be absent. Render `?`, `—`, `(none)`, or a zero count rather than
  erroring. Guard every read with `[ -f ]` BEFORE calling `jq` — a missing file
  makes `jq -s` print a spurious `0` on stdout and exit non-zero, so an
  unguarded `jq … || echo 0` double-counts.
- **Tolerate malformed JSON.** If `jq` fails on a file, print
  `(state file malformed: <path>)` and continue to the next repo.
- **No external API calls.** Do not call `gh`, `curl`, or any network tool.
  The dashboard reads local state only.
- **Never reveal lock holder as "unknown".** If the lock is a non-standard
  value, print it verbatim. The user needs to see what held it.
- **macOS-safe shell.** No `mapfile`, no `readarray`, no `${var,,}` or
  other bash-4 features. Target bash 3.2.
- **Width cap.** Keep each line ≤100 cols so it renders in narrow terminals.
- **Expired entries hidden.** Only active (non-expired) blocks and cooldowns
  are surfaced. Expired entries stay in the file for audit but don't clutter
  the dashboard.
