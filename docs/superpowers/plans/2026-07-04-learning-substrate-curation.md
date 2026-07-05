# Learning Substrate — Curation (Plan 2 of 3) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the pure, unit-testable *write side* of the knowledge base — the four curation scripts (`merge_cards`, `promote_lessons`, `decay_lessons`, `record_regression`) that dedupe, graduate, age out, and log regressions — reusing Plan 1's `card_key`, with no changes to the live agent loop.

**Architecture:** Each script is a pure function over JSONL stores on disk. They reuse the committed `scripts/lib/lesson_checks.sh` (`card_key`, `is_known_check`) as the single source of truth for the dedupe key and the closed-registry safety check. Every mutation **rewrites** its store atomically (temp + `mv`) — never appends — because the merge/promotion logic returns the complete new set. No agent prompt changes: the `lesson-distiller` that calls these, the repo-scan, and live-loop integration are Plan 3.

**Tech Stack:** Bash 3.2, `jq`, `python3` (date arithmetic + schema validation), plain-bash tests under `tests/scripts/`.

**Spec:** `docs/superpowers/specs/2026-07-03-learning-substrate-design.md` (build-order step 3 — Curation mechanics). Depends on Plan 1 (`docs/superpowers/plans/2026-07-03-learning-substrate-foundation.md`), which shipped `rule_card`/`lesson_regression` schemas, `lesson_checks.sh` (`card_key`, `is_known_check`), `select_lessons.sh`, and `check_lessons.sh`.

## Global Constraints

Copied verbatim from the spec/Plan 1. Every task's requirements implicitly include this section.

- **Bash 3.2 compatible.** No `declare -A`, `mapfile`, `${var,,}`, `[[ =~ ]]`. Use `case`, `grep -E`, arrays with `+=`, process substitution, `python3` for date math. **Verify every test under `bash` (the scripts and the harness run under bash 3.2), NOT the interactive `zsh`** — some defects (e.g. a multi-line `X=$(jq '<multiline>' … || echo '[]')` capture) only reproduce under bash 3.2. When a shell var must hold a JSON value for `--argjson`, keep it single-line/compact or route it through a temp file.
- **Script skeleton (every script):** `#!/usr/bin/env bash`; a header-comment usage line; `set -euo pipefail`; `: "${CLAUDE_PLUGIN_ROOT:?CLAUDE_PLUGIN_ROOT must be set}"`; `source "${CLAUDE_PLUGIN_ROOT}/scripts/lib/state.sh"`; a `while [ $# -gt 0 ]; do case "$1" in … esac; done` arg loop; unknown arg → `exit 2`. **Exit codes:** `0` success, `1` recoverable, `2` usage/abort.
- **Directly-invoked → executable.** These four scripts are called by the `lesson-distiller` agent in Plan 3, so each is committed mode **755** (`chmod +x` before `git add`, matching `scripts/scorer/*.sh` and Plan 1's `scripts/lessons/*.sh`). **Tests invoke them via `bash "$SCRIPT"`** (house convention), not direct execution.
- **Rewrite, never append.** Every store mutation writes a `${STORE}.tmp.$$` and `mv`s it over the store. The merge/promotion output is the complete new set — appending would double-count.
- **Single source of truth for the dedupe key.** Use `card_key` from `scripts/lib/lesson_checks.sh` (committed in Plan 1) — never re-implement the key logic in jq. Deterministic key: `det:<check.id>:<sorted-args tojson>`; semantic key: `sem:<lowercased, whitespace-collapsed, trimmed rule>`.
- **Determinism in tests.** Every script that needs "now" accepts `--now`/`--ts` (ISO-8601 `YYYY-MM-DDThh:mm:ssZ`) and defaults to `date -u +%Y-%m-%dT%H:%M:%SZ` only when absent. Tests always pass an explicit timestamp.
- **SAFETY invariant (unchanged from Plan 1):** a deterministic card whose `check.id` is not in the fixed registry (`is_known_check`) is forced to `kind:"semantic"` (and its `check` dropped) at write time — it can execute nothing. Rule cards carry no command/URL/path-outside-repo field.
- **Confidence/threshold constants** (named at the top of each script, tunable): birth `0.5`, confirm-step `+0.15`, cap `1.0`; promotion propose-min `2` distinct repos, graduate-min `3`; decay retire-max `0.25`, decay-days `180`, decay-step `0.1`, retire-by-age `2×decay-days`.
- **No new dependencies.** `jq`, `python3`, `git`, `bash` only.
- **Commit convention:** `feat(lessons): …`, message ending with `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`.
- **Suite green after every task:** `for t in tests/scripts/test_*.sh; do bash "$t" || echo "FAIL: $t"; done`.

---

## Task 1: `merge_cards.sh` — dedupe-merge a candidate into a store

**Files:**
- Create: `scripts/lessons/merge_cards.sh`
- Test: `tests/scripts/test_merge_cards.sh`

**Interfaces:**
- Consumes: `card_key`, `is_known_check` from `scripts/lib/lesson_checks.sh`; `state.sh`.
- Produces: `merge_cards.sh --store STORE_JSONL --card-file CARD_JSON [--now ISO] [--birth 0.5] [--confirm-step 0.15]`. Same `card_key` as an existing card → bump `hits`, raise `confidence` (cap 1.0), refresh `last_confirmed`, union `evidence`/`repos_seen`, revive if `retired`. New key → append with birth defaults. Deterministic card with unknown `check.id` → forced `semantic`. Rewrites the store. Sole caller (Plan 3): `lesson-distiller`.

- [ ] **Step 1: Write the failing test**

Create `tests/scripts/test_merge_cards.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
export CLAUDE_PLUGIN_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
MC="$CLAUDE_PLUGIN_ROOT/scripts/lessons/merge_cards.sh"
tmpdir=$(mktemp -d)
NOW="2026-07-04T00:00:00Z"
store="$tmpdir/lessons.jsonl"; : > "$store"

detcard() { # $1=glob  -> a deterministic file_present card
  jq -nc --arg g "$1" '{id:("news-"+$g),scope:"repo",match:{repo:"apache/airflow"},kind:"deterministic",
    rule:"newsfragment",check:{id:"file_present",args:{glob:$g}},source:"comment",evidence:["PR#1"],
    confidence:0.5,hits:1,repos_seen:["apache/airflow"],status:"active",
    created:"2026-01-01T00:00:00Z",last_confirmed:"2026-01-01T00:00:00Z"}'
}

# --- new card is appended with birth defaults preserved from input ---
detcard "newsfragments/*" > "$tmpdir/c1.json"
bash "$MC" --store "$store" --card-file "$tmpdir/c1.json" --now "$NOW"
[ "$(jq -s length "$store")" -eq 1 ] || { echo "FAIL first insert should yield 1 card"; exit 1; }

# --- same key merges: hits 2, confidence 0.5+0.15=0.65, evidence unioned, last_confirmed refreshed ---
detcard "newsfragments/*" | jq -c '.evidence=["PR#2"] | .confidence=0.9' > "$tmpdir/c2.json"
bash "$MC" --store "$store" --card-file "$tmpdir/c2.json" --now "$NOW"
[ "$(jq -s length "$store")" -eq 1 ] || { echo "FAIL same key must not add a row"; exit 1; }
[ "$(jq -s '.[0].hits' "$store")" -eq 2 ] || { echo "FAIL hits should be 2"; exit 1; }
[ "$(jq -s '.[0].confidence' "$store")" = "0.65" ] || { echo "FAIL confidence should be 0.65 got $(jq -s '.[0].confidence' "$store")"; exit 1; }
[ "$(jq -sc '.[0].evidence' "$store")" = '["PR#1","PR#2"]' ] || { echo "FAIL evidence should union"; exit 1; }
[ "$(jq -s -r '.[0].last_confirmed' "$store")" = "$NOW" ] || { echo "FAIL last_confirmed should refresh to now"; exit 1; }

# --- different check.args VALUE => different key => NOT merged (Plan-1 review carry-forward) ---
detcard "docs/changelog/*" > "$tmpdir/c3.json"
bash "$MC" --store "$store" --card-file "$tmpdir/c3.json" --now "$NOW"
[ "$(jq -s length "$store")" -eq 2 ] || { echo "FAIL differing args value must be a distinct card"; exit 1; }

# --- retired card is revived on merge ---
echo '{"id":"z","scope":"repo","match":{"repo":"apache/airflow"},"kind":"semantic","rule":"reuse util","source":"comment","evidence":[],"confidence":0.3,"hits":1,"repos_seen":["apache/airflow"],"status":"retired","created":"2026-01-01T00:00:00Z","last_confirmed":"2026-01-01T00:00:00Z"}' > "$tmpdir/rev_store.jsonl"
echo '{"id":"z2","scope":"repo","match":{"repo":"apache/airflow"},"kind":"semantic","rule":"reuse util","source":"comment","evidence":[],"confidence":0.3,"hits":1,"repos_seen":["apache/airflow"],"status":"active","created":"2026-01-01T00:00:00Z","last_confirmed":"2026-01-01T00:00:00Z"}' > "$tmpdir/rev_card.json"
bash "$MC" --store "$tmpdir/rev_store.jsonl" --card-file "$tmpdir/rev_card.json" --now "$NOW"
[ "$(jq -s -r '.[0].status' "$tmpdir/rev_store.jsonl")" = "active" ] || { echo "FAIL retired card should revive to active"; exit 1; }

# --- regression: a store whose last line lacks a trailing newline must not lose that card ---
printf '%s' "$(detcard "keep/me/*")" > "$tmpdir/nonl.jsonl"   # NO trailing newline
detcard "other/key/*" > "$tmpdir/other.json"
bash "$MC" --store "$tmpdir/nonl.jsonl" --card-file "$tmpdir/other.json" --now "$NOW"
[ "$(jq -s length "$tmpdir/nonl.jsonl")" -eq 2 ] || { echo "FAIL unterminated last line was dropped on merge"; exit 1; }

# --- SAFETY: unknown check.id forces semantic and drops check ---
jq -nc '{id:"evil","scope":"repo","match":{"repo":"apache/airflow"},kind:"deterministic",rule:"x",check:{id:"run_shell",args:{cmd:"rm -rf /"}},source:"comment",evidence:[],confidence:0.5,hits:1,repos_seen:["apache/airflow"],status:"active",created:"2026-01-01T00:00:00Z",last_confirmed:"2026-01-01T00:00:00Z"}' > "$tmpdir/evil.json"
evstore="$tmpdir/evil_store.jsonl"; : > "$evstore"
bash "$MC" --store "$evstore" --card-file "$tmpdir/evil.json" --now "$NOW"
[ "$(jq -s -r '.[0].kind' "$evstore")" = "semantic" ] || { echo "FAIL unknown check.id must force semantic"; exit 1; }
[ "$(jq -s '.[0] | has("check")' "$evstore")" = "false" ] || { echo "FAIL forced-semantic card must drop check"; exit 1; }

echo "OK test_merge_cards.sh"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/scripts/test_merge_cards.sh`
Expected: FAIL (`merge_cards.sh` not found — `bash "$MC"` errors).

- [ ] **Step 3: Write the script**

Create `scripts/lessons/merge_cards.sh`:

```bash
#!/usr/bin/env bash
# merge_cards.sh --store STORE_JSONL --card-file CARD_JSON [--now ISO] [--birth 0.5] [--confirm-step 0.15]
# Dedupe-merge one candidate rule card into a JSONL store (sole caller: lesson-distiller).
# Same card_key -> bump hits, raise confidence (cap 1.0), refresh last_confirmed,
# union evidence/repos_seen, revive if retired. New key -> append with birth defaults.
# SAFETY: a deterministic card whose check.id is not in the fixed registry is forced
# to kind=semantic (its check is dropped) so it can execute nothing. Rewrites the store.
set -euo pipefail
: "${CLAUDE_PLUGIN_ROOT:?CLAUDE_PLUGIN_ROOT must be set}"
source "${CLAUDE_PLUGIN_ROOT}/scripts/lib/state.sh"
source "${CLAUDE_PLUGIN_ROOT}/scripts/lib/lesson_checks.sh"

STORE=""; CARD_FILE=""; NOW=""; BIRTH="0.5"; STEP="0.15"
while [ $# -gt 0 ]; do
  case "$1" in
    --store)        STORE="$2"; shift 2 ;;
    --card-file)    CARD_FILE="$2"; shift 2 ;;
    --now)          NOW="$2"; shift 2 ;;
    --birth)        BIRTH="$2"; shift 2 ;;
    --confirm-step) STEP="$2"; shift 2 ;;
    *) echo "merge_cards.sh: unknown arg: $1" >&2; exit 2 ;;
  esac
done
[ -n "$STORE" ] || { echo "--store required" >&2; exit 2; }
[ -n "$CARD_FILE" ] && [ -f "$CARD_FILE" ] || { echo "--card-file FILE required" >&2; exit 2; }
[ -n "$NOW" ] || NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)

card=$(cat "$CARD_FILE")

# SAFETY: force semantic if a deterministic card names an unknown check.
cid=$(printf '%s' "$card" | jq -r 'if .kind == "deterministic" then (.check.id // "") else "" end')
if [ -n "$cid" ] && ! is_known_check "$cid"; then
  card=$(printf '%s' "$card" | jq -c '.kind = "semantic" | del(.check)')
fi
newkey=$(card_key "$card")

mkdir -p "$(dirname "$STORE")"
[ -f "$STORE" ] || : > "$STORE"

merged=""; tmpf="${STORE}.tmp.$$"; : > "$tmpf"
# `|| [ -n "$line" ]` processes a final line with no trailing newline (a store an
# external/manual editor may produce) — without it, read returns 1 at EOF on the
# partial line and the loop drops that card.
while IFS= read -r line || [ -n "$line" ]; do
  [ -n "$line" ] || continue
  if [ -z "$merged" ] && [ "$(card_key "$line")" = "$newkey" ]; then
    line=$(jq -nc --argjson old "$line" --argjson new "$card" --arg now "$NOW" --argjson step "$STEP" '
      $old
      | .hits          = ((.hits // 0) + 1)
      | .confidence    = ([ (.confidence // 0) + $step, 1 ] | min)
      | .last_confirmed = $now
      | .status        = (if .status == "retired" then "active" else .status end)
      | .evidence      = (((.evidence // []) + ($new.evidence // [])) | unique)
      | .repos_seen    = (((.repos_seen // []) + ($new.repos_seen // [])) | unique)')
    merged=1
  fi
  printf '%s\n' "$line" >> "$tmpf"
done < "$STORE"

if [ -z "$merged" ]; then
  printf '%s\n' "$(printf '%s' "$card" | jq -c --arg now "$NOW" --argjson birth "$BIRTH" '
    .confidence     = (.confidence // $birth)
    | .hits         = (.hits // 1)
    | .status       = (.status // "active")
    | .created      = (.created // $now)
    | .last_confirmed = (.last_confirmed // $now)
    | .repos_seen   = (if (.repos_seen // []) == []
                       then (if (.match.repo // "") == "" then [] else [.match.repo] end)
                       else .repos_seen end)
    | .evidence     = (.evidence // [])')" >> "$tmpf"
fi

mv "$tmpf" "$STORE"
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/scripts/test_merge_cards.sh`
Expected: `OK test_merge_cards.sh`

- [ ] **Step 5: Commit**

```bash
chmod +x scripts/lessons/merge_cards.sh
git add scripts/lessons/merge_cards.sh tests/scripts/test_merge_cards.sh
git commit -m "feat(lessons): merge_cards.sh — dedupe-merge via card_key

Same card_key -> bump hits, raise confidence (cap 1.0), refresh last_confirmed,
union evidence/repos_seen, revive retired. New key -> birth defaults. Unknown
check.id forced to semantic. Rewrites the store.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: `promote_lessons.sh` — graduated cross-repo promotion

**Files:**
- Create: `scripts/lessons/promote_lessons.sh`
- Test: `tests/scripts/test_promote_lessons.sh`

**Interfaces:**
- Consumes: `card_key` from `scripts/lib/lesson_checks.sh`; `state.sh`.
- Produces: `promote_lessons.sh --repo-store FILE [--repo-store FILE ...] --global-store FILE [--now ISO] [--propose-min 2] [--graduate-min 3]`. A `repo`-scoped rule whose `card_key` recurs across ≥`propose-min` **distinct** repos → upsert a `global-candidate` (advisory) into the global store; a card reaching ≥`graduate-min` distinct repos → `global` (enforced). Never downgrades an existing `global`. Rewrites the global store. Sole caller (Plan 3): `lesson-distiller`.

- [ ] **Step 1: Write the failing test**

Create `tests/scripts/test_promote_lessons.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
export CLAUDE_PLUGIN_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PL="$CLAUDE_PLUGIN_ROOT/scripts/lessons/promote_lessons.sh"
tmpdir=$(mktemp -d)
NOW="2026-07-04T00:00:00Z"

# same semantic rule ("reuse the util") in each repo store -> same card_key
repocard() { jq -nc --arg id "$1" --arg repo "$2" '{id:$id,scope:"repo",match:{repo:$repo},kind:"semantic",rule:"reuse the util",source:"comment",evidence:[],confidence:0.8,hits:1,repos_seen:[$repo],status:"active",created:"2026-01-01T00:00:00Z",last_confirmed:"2026-01-01T00:00:00Z"}'; }
repocard idA a/one   > "$tmpdir/rA.jsonl"
repocard idB b/two   > "$tmpdir/rB.jsonl"
repocard idC c/three > "$tmpdir/rC.jsonl"
glob="$tmpdir/lessons_global.jsonl"; : > "$glob"

# --- 2 distinct repos -> one global-candidate (advisory), repos_seen unioned ---
bash "$PL" --repo-store "$tmpdir/rA.jsonl" --repo-store "$tmpdir/rB.jsonl" --global-store "$glob" --now "$NOW"
[ "$(jq -s length "$glob")" -eq 1 ] || { echo "FAIL 2 repos should yield 1 global row"; exit 1; }
[ "$(jq -s -r '.[0].scope' "$glob")" = "global-candidate" ] || { echo "FAIL 2 repos should be global-candidate got $(jq -s -r '.[0].scope' "$glob")"; exit 1; }
[ "$(jq -s -rc '.[0].repos_seen | sort | join(",")' "$glob")" = "a/one,b/two" ] || { echo "FAIL candidate repos_seen"; exit 1; }

# --- 3rd distinct repo -> graduate to global (enforced), still one row ---
bash "$PL" --repo-store "$tmpdir/rA.jsonl" --repo-store "$tmpdir/rB.jsonl" --repo-store "$tmpdir/rC.jsonl" --global-store "$glob" --now "$NOW"
[ "$(jq -s length "$glob")" -eq 1 ] || { echo "FAIL graduation must upsert, not add a row"; exit 1; }
[ "$(jq -s -r '.[0].scope' "$glob")" = "global" ] || { echo "FAIL 3 repos should graduate to global"; exit 1; }
[ "$(jq -s -rc '.[0].repos_seen | sort | join(",")' "$glob")" = "a/one,b/two,c/three" ] || { echo "FAIL global repos_seen"; exit 1; }

# --- a below-threshold round (1 repo) must NOT downgrade or drop the existing global ---
bash "$PL" --repo-store "$tmpdir/rA.jsonl" --global-store "$glob" --now "$NOW"
[ "$(jq -s length "$glob")" -eq 1 ] || { echo "FAIL existing global dropped on below-threshold round"; exit 1; }
[ "$(jq -s -r '.[0].scope' "$glob")" = "global" ] || { echo "FAIL existing global downgraded"; exit 1; }

# --- a rule in only ONE repo never promotes ---
glob2="$tmpdir/g2.jsonl"; : > "$glob2"
bash "$PL" --repo-store "$tmpdir/rA.jsonl" --global-store "$glob2" --now "$NOW"
[ "$(jq -s length "$glob2")" -eq 0 ] || { echo "FAIL single-repo rule must not promote"; exit 1; }

echo "OK test_promote_lessons.sh"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/scripts/test_promote_lessons.sh`
Expected: FAIL (`promote_lessons.sh` not found).

- [ ] **Step 3: Write the script**

Create `scripts/lessons/promote_lessons.sh`:

```bash
#!/usr/bin/env bash
# promote_lessons.sh --repo-store FILE [--repo-store FILE ...] --global-store FILE
#                    [--now ISO] [--propose-min 2] [--graduate-min 3]
# Graduated cross-repo promotion (sole caller: lesson-distiller). A repo-scoped
# rule whose card_key recurs across >= propose-min DISTINCT repos becomes a
# global-candidate (advisory); a card reaching >= graduate-min distinct repos
# graduates to global (enforced). Never downgrades an existing global.
# Reuses card_key (single source of truth) to annotate both repo cards and the
# existing global store, then upserts by key. Rewrites the global store (the
# reduce returns the complete merged set).
#
# NOTE (bash 3.2): the two `jq -s` results below are written to temp FILES and read
# back via `--argjson … "$(cat FILE)"`. Capturing a multi-line jq result directly —
# `X=$(jq -s '<multiline>' … 2>/dev/null || echo '[]')` — hits a bash 3.2 (macOS
# default) command-substitution parser bug that yields a bogus number (a 1-element
# array reads as the integer 20). The redirect-to-file form keeps the `||` off the
# `$( … )` and is bash-3.2-safe. VERIFY THIS SCRIPT UNDER `bash`, NOT zsh.
set -euo pipefail
: "${CLAUDE_PLUGIN_ROOT:?CLAUDE_PLUGIN_ROOT must be set}"
source "${CLAUDE_PLUGIN_ROOT}/scripts/lib/state.sh"
source "${CLAUDE_PLUGIN_ROOT}/scripts/lib/lesson_checks.sh"

GLOBAL=""; NOW=""; PMIN="2"; GMIN="3"; REPO_STORES=()
while [ $# -gt 0 ]; do
  case "$1" in
    --repo-store)   REPO_STORES+=("$2"); shift 2 ;;
    --global-store) GLOBAL="$2"; shift 2 ;;
    --now)          NOW="$2"; shift 2 ;;
    --propose-min)  PMIN="$2"; shift 2 ;;
    --graduate-min) GMIN="$2"; shift 2 ;;
    *) echo "promote_lessons.sh: unknown arg: $1" >&2; exit 2 ;;
  esac
done
[ -n "$GLOBAL" ] || { echo "--global-store required" >&2; exit 2; }
[ -n "$NOW" ] || NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
mkdir -p "$(dirname "$GLOBAL")"
[ -f "$GLOBAL" ] || : > "$GLOBAL"

# Annotate every card in the given store files with its card_key -> {k, c} lines.
annotate() {
  local out="$1"; shift
  local s c k
  : > "$out"
  for s in "$@"; do
    [ -n "$s" ] && [ -f "$s" ] || continue
    while IFS= read -r c || [ -n "$c" ]; do
      [ -n "$c" ] || continue
      k=$(card_key "$c")
      jq -nc --arg k "$k" --argjson c "$c" '{k: $k, c: $c}' >> "$out"
    done < "$s"
  done
}

REPO_ANNOT="${GLOBAL}.repo_annot.$$"
EX_ANNOT="${GLOBAL}.ex_annot.$$"
annotate "$REPO_ANNOT" "${REPO_STORES[@]:-}"
annotate "$EX_ANNOT" "$GLOBAL"

# Group repo cards by key; count DISTINCT repos; keep a representative (highest-confidence) card.
# Results go to temp FILES (not shell vars) — see the bash-3.2 NOTE in the header.
GROUPS_FILE="${GLOBAL}.groups.$$"
jq -s '
  map(select(.c.scope == "repo"))
  | group_by(.k)
  | map({ key:   .[0].k,
          repos: (map(.c.match.repo // "") | unique | map(select(. != ""))),
          rep:   (max_by(.c.confidence).c) })' "$REPO_ANNOT" > "$GROUPS_FILE" 2>/dev/null || echo '[]' > "$GROUPS_FILE"
EXISTING_FILE="${GLOBAL}.existing.$$"
jq -s '.' "$EX_ANNOT" > "$EXISTING_FILE" 2>/dev/null || echo '[]' > "$EXISTING_FILE"

tmpf="${GLOBAL}.tmp.$$"
jq -nc --argjson groups "$(cat "$GROUPS_FILE")" --argjson existing "$(cat "$EXISTING_FILE")" \
       --arg now "$NOW" --argjson pmin "$PMIN" --argjson gmin "$GMIN" '
  ($existing | map({(.k): .c}) | add // {}) as $gx
  | reduce ($groups[] | select((.repos | length) >= $pmin)) as $g ($gx;
      (.[$g.key] // ($g.rep
                     | .scope  = "global-candidate"
                     | .id     = ($g.rep.id + "-global")
                     | .source = "outcome"
                     | .created = $now)) as $base
      | .[$g.key] = ( $base
          | .repos_seen    = (((.repos_seen // []) + $g.repos) | unique)
          | .last_confirmed = $now
          | .confidence    = ([ (.confidence // 0), ($g.rep.confidence // 0) ] | max)
          | .scope         = (if .scope == "global" then "global"
                              elif ($g.repos | length) >= $gmin then "global"
                              else "global-candidate" end)
          | .status        = (.status // "active")
          | .hits          = (.hits // 1) ) )
  | [ .[] ]' | jq -c '.[]' > "$tmpf"
mv "$tmpf" "$GLOBAL"
rm -f "$REPO_ANNOT" "$EX_ANNOT" "$GROUPS_FILE" "$EXISTING_FILE"
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/scripts/test_promote_lessons.sh`
Expected: `OK test_promote_lessons.sh`

- [ ] **Step 5: Commit**

```bash
chmod +x scripts/lessons/promote_lessons.sh
git add scripts/lessons/promote_lessons.sh tests/scripts/test_promote_lessons.sh
git commit -m "feat(lessons): promote_lessons.sh — graduated cross-repo promotion

card_key in >=2 distinct repos -> global-candidate (advisory); >=3 -> global
(enforced). Never downgrades an existing global. Reuses card_key as the single
source of truth; rewrites the global store.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: `decay_lessons.sh` — age-based confidence decay + retirement

**Files:**
- Create: `scripts/lessons/decay_lessons.sh`
- Test: `tests/scripts/test_decay_lessons.sh`

**Interfaces:**
- Consumes: `state.sh`; `python3` for date arithmetic.
- Produces: `decay_lessons.sh --store FILE [--now ISO] [--retire-max 0.25] [--decay-days 180] [--decay-step 0.1]`. A card not confirmed within `decay-days` loses `decay-step` confidence (floored at 0); a card whose confidence falls below `retire-max`, or whose age exceeds `2×decay-days`, is set `status:"retired"`. Cards with no `last_confirmed` are left untouched. Rewrites the store. Sole caller (Plan 3): `lesson-distiller`.

- [ ] **Step 1: Write the failing test**

Create `tests/scripts/test_decay_lessons.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
export CLAUDE_PLUGIN_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
DL="$CLAUDE_PLUGIN_ROOT/scripts/lessons/decay_lessons.sh"
tmpdir=$(mktemp -d)
NOW="2026-07-04T00:00:00Z"
store="$tmpdir/lessons.jsonl"

card() { # $1=id $2=confidence $3=last_confirmed $4=status
  jq -nc --arg id "$1" --argjson c "$2" --arg lc "$3" --arg st "$4" \
    '{id:$id,scope:"repo",match:{repo:"x/y"},kind:"semantic",rule:("r-"+$id),source:"comment",
      evidence:[],confidence:$c,hits:1,repos_seen:["x/y"],status:$st,created:"2025-01-01T00:00:00Z",last_confirmed:$lc}'
}
{
  card fresh   0.9  "2026-07-01T00:00:00Z" active   # age 3 days  -> untouched
  card decayed 0.5  "2026-01-01T00:00:00Z" active   # age ~184>180 -> 0.5-0.1=0.4, stays active
  card lowconf 0.30 "2026-01-01T00:00:00Z" active   # age ~184>180 -> 0.30-0.1=0.20<0.25 -> retired
  card ancient 0.9  "2025-01-01T00:00:00Z" active   # age ~549>360 -> retired (by age)
  jq -nc '{id:"nolc",scope:"repo",match:{repo:"x/y"},kind:"semantic",rule:"r-nolc",source:"comment",evidence:[],confidence:0.9,hits:1,repos_seen:["x/y"],status:"active",created:"2025-01-01T00:00:00Z"}'  # no last_confirmed -> untouched
} > "$store"

bash "$DL" --store "$store" --now "$NOW"

get() { jq -s -r --arg id "$1" --arg f "$2" '.[] | select(.id==$id) | .[$f] | tostring' "$store"; }
[ "$(get fresh confidence)" = "0.9" ] && [ "$(get fresh status)" = "active" ] || { echo "FAIL fresh card must be untouched"; exit 1; }
[ "$(get decayed confidence)" = "0.4" ] && [ "$(get decayed status)" = "active" ] || { echo "FAIL decayed card should be 0.4/active got $(get decayed confidence)/$(get decayed status)"; exit 1; }
[ "$(get lowconf status)" = "retired" ] || { echo "FAIL lowconf card should retire (conf<retire-max)"; exit 1; }
[ "$(get ancient status)" = "retired" ] || { echo "FAIL ancient card should retire (age>2*decay-days)"; exit 1; }
[ "$(get nolc confidence)" = "0.9" ] && [ "$(get nolc status)" = "active" ] || { echo "FAIL card without last_confirmed must be untouched"; exit 1; }

echo "OK test_decay_lessons.sh"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/scripts/test_decay_lessons.sh`
Expected: FAIL (`decay_lessons.sh` not found).

- [ ] **Step 3: Write the script**

Create `scripts/lessons/decay_lessons.sh`:

```bash
#!/usr/bin/env bash
# decay_lessons.sh --store FILE [--now ISO] [--retire-max 0.25] [--decay-days 180] [--decay-step 0.1]
# Age-based decay (sole caller: lesson-distiller). A card not confirmed within
# decay-days loses decay-step confidence (floored at 0); a card whose confidence
# falls below retire-max, or whose age exceeds 2*decay-days, is retired. Cards
# with no last_confirmed are left untouched. Rewrites the store.
set -euo pipefail
: "${CLAUDE_PLUGIN_ROOT:?CLAUDE_PLUGIN_ROOT must be set}"
source "${CLAUDE_PLUGIN_ROOT}/scripts/lib/state.sh"

STORE=""; NOW=""; RETIRE="0.25"; DAYS="180"; STEP="0.1"
while [ $# -gt 0 ]; do
  case "$1" in
    --store)      STORE="$2"; shift 2 ;;
    --now)        NOW="$2"; shift 2 ;;
    --retire-max) RETIRE="$2"; shift 2 ;;
    --decay-days) DAYS="$2"; shift 2 ;;
    --decay-step) STEP="$2"; shift 2 ;;
    *) echo "decay_lessons.sh: unknown arg: $1" >&2; exit 2 ;;
  esac
done
[ -n "$STORE" ] || { echo "--store required" >&2; exit 2; }
[ -f "$STORE" ] || exit 0     # nothing to decay
[ -n "$NOW" ] || NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# integer days between an ISO timestamp ($1) and NOW; 0 on parse failure.
age_days() {
  python3 - "$NOW" "$1" <<'PY'
import sys, datetime
def parse(s): return datetime.datetime.fromisoformat(s.replace('Z', '+00:00'))
try:
    print(max(0, (parse(sys.argv[1]) - parse(sys.argv[2])).days))
except Exception:
    print(0)
PY
}

tmpf="${STORE}.tmp.$$"; : > "$tmpf"
while IFS= read -r card || [ -n "$card" ]; do
  [ -n "$card" ] || continue
  lc=$(printf '%s' "$card" | jq -r '.last_confirmed // ""')
  if [ -z "$lc" ]; then
    printf '%s\n' "$card" >> "$tmpf"
    continue
  fi
  age=$(age_days "$lc")
  printf '%s\n' "$(printf '%s' "$card" | jq -c \
    --argjson age "$age" --argjson days "$DAYS" --argjson step "$STEP" --argjson retire "$RETIRE" '
    (if $age > $days then .confidence = ([ (.confidence - $step), 0 ] | max) else . end)
    | (if (.confidence < $retire or $age > ($days * 2)) then .status = "retired" else . end)')" >> "$tmpf"
done < "$STORE"
mv "$tmpf" "$STORE"
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/scripts/test_decay_lessons.sh`
Expected: `OK test_decay_lessons.sh`

- [ ] **Step 5: Commit**

```bash
chmod +x scripts/lessons/decay_lessons.sh
git add scripts/lessons/decay_lessons.sh tests/scripts/test_decay_lessons.sh
git commit -m "feat(lessons): decay_lessons.sh — age-based decay + retirement

Unconfirmed past decay-days -> lose decay-step confidence; below retire-max or
older than 2*decay-days -> retired. last_confirmed absent -> untouched. Rewrites.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: `record_regression.sh` — append a regression event

**Files:**
- Create: `scripts/lessons/record_regression.sh`
- Test: `tests/scripts/test_record_regression.sh`

**Interfaces:**
- Consumes: `state.sh` (`global_dir`).
- Produces: `record_regression.sh --repo OWNER/REPO --rule-id ID --kind (shipped_violation|maintainer_reraise) [--pr-url URL] [--ts ISO]`. Appends one line to `~/.superhuman/global/lesson_regressions.jsonl` matching `lesson_regression.schema.json`. Rejects an unknown `--kind` with exit 2. Append-only (like `record_outcome.sh`). Callers (Plan 3): `lesson-distiller` (maintainer_reraise) and `merge-probability-scorer` (shipped_violation).

- [ ] **Step 1: Write the failing test**

Create `tests/scripts/test_record_regression.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
export CLAUDE_PLUGIN_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
source "$CLAUDE_PLUGIN_ROOT/scripts/lib/state.sh"
RR="$CLAUDE_PLUGIN_ROOT/scripts/lessons/record_regression.sh"
SCHEMA="$CLAUDE_PLUGIN_ROOT/schemas/lesson_regression.schema.json"
tmpdir=$(mktemp -d)
TS="2026-07-04T00:00:00Z"

# Redirect state to a temp HOME so we never touch real ~/.superhuman.
export HOME="$tmpdir"
log="$tmpdir/.superhuman/global/lesson_regressions.jsonl"

# --- valid append writes one schema-valid line ---
bash "$RR" --repo apache/airflow --rule-id apache-airflow-newsfragment --kind shipped_violation --pr-url "https://github.com/apache/airflow/pull/1" --ts "$TS"
[ -f "$log" ] || { echo "FAIL log not created"; exit 1; }
[ "$(wc -l < "$log" | tr -d ' ')" -eq 1 ] || { echo "FAIL should have 1 line"; exit 1; }
jq -c 'select(.rule_id=="apache-airflow-newsfragment" and .kind=="shipped_violation" and .repo=="apache/airflow" and .ts=="'"$TS"'")' "$log" | grep -q . || { echo "FAIL line content wrong"; exit 1; }
head -1 "$log" > "$tmpdir/line.json"
validate_json "$SCHEMA" "$tmpdir/line.json" || { echo "FAIL line must validate against lesson_regression schema"; exit 1; }

# --- append is additive (second kind) ---
bash "$RR" --repo apache/airflow --rule-id apache-airflow-newsfragment --kind maintainer_reraise --ts "$TS"
[ "$(wc -l < "$log" | tr -d ' ')" -eq 2 ] || { echo "FAIL should append, not overwrite"; exit 1; }

# --- unknown --kind rejected with exit 2 ---
set +e
bash "$RR" --repo apache/airflow --rule-id x --kind bogus --ts "$TS" 2>/dev/null; rc=$?
set -e
[ "$rc" -eq 2 ] || { echo "FAIL unknown kind must exit 2, got $rc"; exit 1; }
[ "$(wc -l < "$log" | tr -d ' ')" -eq 2 ] || { echo "FAIL rejected call must not write"; exit 1; }

# --- missing --rule-id rejected ---
set +e
bash "$RR" --repo apache/airflow --kind shipped_violation --ts "$TS" 2>/dev/null; rc=$?
set -e
[ "$rc" -eq 2 ] || { echo "FAIL missing rule-id must exit 2, got $rc"; exit 1; }

echo "OK test_record_regression.sh"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/scripts/test_record_regression.sh`
Expected: FAIL (`record_regression.sh` not found).

- [ ] **Step 3: Write the script**

Create `scripts/lessons/record_regression.sh`:

```bash
#!/usr/bin/env bash
# record_regression.sh --repo OWNER/REPO --rule-id ID
#                      --kind (shipped_violation|maintainer_reraise) [--pr-url URL] [--ts ISO]
# Append-only JSONL to ~/.superhuman/global/lesson_regressions.jsonl — the
# "known enforced rule violated at submission / re-raised by a maintainer" alarm.
# Writers: lesson-distiller (maintainer_reraise), merge-probability-scorer (shipped_violation).
set -euo pipefail
: "${CLAUDE_PLUGIN_ROOT:?CLAUDE_PLUGIN_ROOT must be set}"
source "${CLAUDE_PLUGIN_ROOT}/scripts/lib/state.sh"

REPO=""; RULE_ID=""; KIND=""; PR_URL=""; TS=""
while [ $# -gt 0 ]; do
  case "$1" in
    --repo)    REPO="$2"; shift 2 ;;
    --rule-id) RULE_ID="$2"; shift 2 ;;
    --kind)    KIND="$2"; shift 2 ;;
    --pr-url)  PR_URL="$2"; shift 2 ;;
    --ts)      TS="$2"; shift 2 ;;
    *) echo "record_regression.sh: unknown arg: $1" >&2; exit 2 ;;
  esac
done
[ -n "$REPO" ]    || { echo "--repo required" >&2; exit 2; }
[ -n "$RULE_ID" ] || { echo "--rule-id required" >&2; exit 2; }
case "$KIND" in
  shipped_violation|maintainer_reraise) : ;;
  *) echo "record_regression.sh: --kind must be shipped_violation|maintainer_reraise" >&2; exit 2 ;;
esac
[ -n "$TS" ] || TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)

GD=$(global_dir); mkdir -p "$GD"
LOG="$GD/lesson_regressions.jsonl"
jq -nc --arg rid "$RULE_ID" --arg repo "$REPO" --arg pr "$PR_URL" --arg kind "$KIND" --arg ts "$TS" \
  '{rule_id: $rid, repo: $repo, pr_url: $pr, kind: $kind, ts: $ts}' >> "$LOG"
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/scripts/test_record_regression.sh`
Expected: `OK test_record_regression.sh`

- [ ] **Step 5: Run the FULL suite and commit**

Run: `for t in tests/scripts/test_*.sh; do bash "$t" || echo "FAIL: $t"; done`
Expected: every line `OK …`, no `FAIL:` lines (Plan 1's 42 + these 4 = 46 test files green).

```bash
chmod +x scripts/lessons/record_regression.sh
git add scripts/lessons/record_regression.sh tests/scripts/test_record_regression.sh
git commit -m "feat(lessons): record_regression.sh — the did-we-regress alarm

Appends {rule_id,repo,pr_url,kind,ts} to global/lesson_regressions.jsonl;
rejects unknown --kind. The 'same comment recurred = learning failed' signal.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Self-Review

**1. Spec coverage (build-order step 3 — Curation mechanics):**
- `merge_cards` (dedupe/bump/union/revive/force-semantic) → Task 1. ✅
- `promote_lessons` (graduated repo→candidate→global, no downgrade) → Task 2. ✅
- `decay_lessons` (age decay + retire) → Task 3. ✅
- `record_regression` (the regression alarm) → Task 4. ✅
- Deferred to Plan 3 (correctly out of scope): `scripts/profiler/scan_structure.sh` + `repo_scan.json` emission; the `lesson-distiller` agent (seed + curate) and its registration; all prevent/enforce/orchestrate wiring. The `contradiction-demotion` behavior (demote an enforced rule to candidate on contradicting evidence) is the distiller's judgment (Plan 3), built on `merge_cards`/`decay_lessons` primitives here.

**2. Placeholder scan:** No TBD/TODO. Every step ships complete, smoke-tested code and an exact command with expected output. ✅

**3. Type consistency:** `card_key`/`is_known_check` (from Plan 1's `lesson_checks.sh`) are used with their committed signatures. The rule-card fields mutated here (`hits, confidence, last_confirmed, status, evidence, repos_seen, scope, id, source, created, check, kind, match.repo`) all exist in `rule_card.schema.json`; `scope` transitions use only sanctioned enum values (`repo → global-candidate → global`); `status` uses `active`/`retired`; regression `kind` uses the `lesson_regression.schema.json` enum. Every store mutation rewrites via `${STORE}.tmp.$$` + `mv`, per Global Constraints. ✅

---

## Roadmap — Plan 3 (Producer + Scan + Integration)

Plan 2's four scripts are the deterministic curation mechanism. Plan 3 adds the producer that calls them and wires the substrate into the live loop:
- `scripts/profiler/scan_structure.sh` + `repo_scan.json` emission in `repo-profiler` (the scan that grounds the dossier).
- `agents/lesson-distiller.md` (NEW): **seed** mode (author `dossier.md` + scan rule-cards from `repo_scan.json`) and **curate** mode (mine comments/outcome → `merge_cards` → `promote_lessons` → `decay_lessons`, and demote-on-contradiction). Register in `.claude-plugin/plugin.json` + Codex `SKILL.md`.
- `planner`/`builder` mandatory injection (prevent); `merge-probability-scorer` convention-compliance cap + `record_regression` on shipped violations (enforce); `resolve-comments` hands classified comments to the distiller; `opensource-contributor` sequences the distiller phases.
- `import_sorted` check added to the registry; `SHARED_STATE.md`, dashboard Learning panel, `README`/`CHANGELOG`; bump both manifests to 0.8.0.
- **Plan-1 review carry-forwards** (already recorded in the Plan-1 doc): `check_lessons.sh` `--enforce-min` numeric guard; `select_lessons.sh` caller asserts `--changed-files` exists.

### Plan-2 whole-branch review carry-forwards (for Plan 3's distiller)

The final review confirmed the curation primitives compose coherently and deliberately leave three
transitions to the Plan-3 `lesson-distiller` — make these explicit distiller-contract requirements so
the read-side `enforced` predicate (`status==active ∧ confidence≥0.75 ∧ scope∈{repo,global}`) stays coherent:
- **Emit candidate cards as `status:"active"`.** `merge_cards` birth-defaults an *absent* status to `active`,
  but writes an explicit `retired`/`demoted` through as-is — a card minted non-active would be stranded un-enforced.
- **Own the `demoted`→`active` re-confirmation.** The write-side primitives never move a card *out* of `demoted`
  (merge revives only `retired`→`active`; decay only moves toward `retired`; promote preserves existing status).
  So `demoted`'s only exit is retirement-by-age unless the distiller explicitly re-confirms it.
- **Own contradiction-demotion itself** (spec's Plan-3 job): set `demoted` on an enforced rule the current
  repo's merged PRs disprove.

**Post-review hardening (applied, `d50109c`):** all three store-mutators (`merge_cards`, `promote_lessons`,
`decay_lessons`) now **abort loudly + `trap … EXIT` clean up their temp file on malformed input** — consistent
behavior, no silent corruption write-through (merge) and no `.tmp` leak into `~/.superhuman/` (decay). A shared
temp-file-safety helper in `state.sh` is a reasonable Plan-3 refactor so future store-mutating scripts inherit it.

## Next steps

1. Execute Plan 2 (subagent-driven).
2. When green, write Plan 3 from this roadmap + the spec.
