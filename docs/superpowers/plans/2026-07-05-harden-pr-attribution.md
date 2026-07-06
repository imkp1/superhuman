# Rogue-Proof PR-Body Attribution Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the deterministic footer the single source of truth for PR-body attribution by having `pr_body_with_attribution.sh` scrub any model-authored attribution before it appends (or suppresses) the canonical footer.

**Architecture:** Add a `scrub_attribution()` awk pass to the existing Phase 6 filter. It strips model-authored attribution lines (full-line match: attribution verb + tool/agent name, plus explicit catches), collapses the whitespace/`---` it leaves behind, then runs the existing `SUPERHUMAN_ATTRIBUTION` enable/append logic on the scrubbed body. Scrub runs regardless of the flag, so "off" means no attribution at all and idempotency holds by construction.

**Tech Stack:** Bash, awk (macOS BWK awk 20200816 / gawk compatible), `jq`. Tests are plain-bash under `tests/scripts/`.

## Global Constraints

- Scrub runs **always**, before the flag check. The flag only controls whether the canonical footer is re-appended.
- Canonical footer text is unchanged: `🤖 Opened with [Superhuman](<url>), an open-source contribution agent.` where `<url>` = `.homepage // .repository` from `.claude-plugin/plugin.json`, fallback `https://github.com/gaurav0107/superhuman`.
- `SUPERHUMAN_ATTRIBUTION` disabling values (case-insensitive): `off`, `false`, `0`, `no`. Any other value (or unset) = enabled.
- A line is scrubbed only if the **whole line** matches. Match = (attribution **verb**) AND (tool/agent **name**), OR an explicit catch. Verbs: `prepared|generated|opened|created|made|built|authored|written|produced|assisted|with assistance`. Names: `superhuman|claude|anthropic|ai agent|contribution agent|contribution plugin`. Explicit catches: substring `opened with [superhuman]`; `github.com/gaurav0107/superhuman`; line-leading `co-authored-by:` (after stripping leading `>`/`<sub>`/space); `noreply@anthropic.com`; `claude.ai/code`; `claude.com/claude-code`; a line containing `🤖` and `generated with`. All matching is case-insensitive.
- Commits are never touched by this filter (unchanged; commit-scoped rules live in `builder.md`).
- Tests: plain bash, `set -euo pipefail`, string/`grep` assertions, end with `OK <name>`.

---

### Task 1: Add `scrub_attribution()` to the attribution filter

**Files:**
- Modify (full rewrite): `scripts/orchestrator/pr_body_with_attribution.sh`
- Test (rewrite): `tests/scripts/test_pr_body_with_attribution.sh`

**Interfaces:**
- Consumes: stdin (PR body), env `SUPERHUMAN_ATTRIBUTION`, `CLAUDE_PLUGIN_ROOT` (to read `plugin.json`).
- Produces: stdout — the scrubbed body plus the canonical footer (enabled) or the scrubbed body alone (disabled). CLI contract unchanged: `printf '%s' "$BODY" | pr_body_with_attribution.sh`. Wired at `agents/opensource-contributor.md` Phase 6 (no change needed there).

- [ ] **Step 1: Rewrite the test to specify scrub behavior**

Replace the entire contents of `tests/scripts/test_pr_body_with_attribution.sh` with:

```bash
#!/usr/bin/env bash
# tests/scripts/test_pr_body_with_attribution.sh
set -euo pipefail
export CLAUDE_PLUGIN_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT="$CLAUDE_PLUGIN_ROOT/scripts/orchestrator/pr_body_with_attribution.sh"

fail() { echo "FAIL: $1"; exit 1; }
marker_count() { printf '%s' "$1" | grep -cF 'Opened with [Superhuman]'; }

BASE='## Summary
Fixes the thing.'

# 1. Default (unset): footer appended, base body preserved, repo url present, one marker.
unset SUPERHUMAN_ATTRIBUTION 2>/dev/null || true
OUT="$(printf '%s' "$BASE" | bash "$SCRIPT")"
printf '%s' "$OUT" | grep -qF 'Fixes the thing.'                || fail "default: base body lost"
printf '%s' "$OUT" | grep -qF 'github.com/gaurav0107/superhuman' || fail "default: repo url missing"
[ "$(marker_count "$OUT")" = "1" ]                              || fail "default: marker count != 1"

# 2a. Disable + clean body: returned byte-for-byte.
for v in off OFF false 0 no; do
  OUT="$(printf '%s' "$BASE" | SUPERHUMAN_ATTRIBUTION="$v" bash "$SCRIPT")"
  [ "$OUT" = "$BASE" ] || fail "disable '$v': clean body not returned verbatim"
done

# 2b. Disable + rogue attribution: rogue line scrubbed, no footer, base kept.
ROGUE="$BASE
<sub>Prepared with assistance from the Superhuman open-source contribution plugin.</sub>"
OUT="$(printf '%s' "$ROGUE" | SUPERHUMAN_ATTRIBUTION=off bash "$SCRIPT")"
printf '%s' "$OUT" | grep -qiF 'Prepared with assistance' && fail "disable: rogue line not scrubbed"
printf '%s' "$OUT" | grep -qiF 'superhuman'                && fail "disable: superhuman mention remains"
printf '%s' "$OUT" | grep -qF  'Fixes the thing.'          || fail "disable: base body lost"

# 3. Idempotency: re-running a footered body yields the same output, one marker.
WITH_FOOTER="$(printf '%s' "$BASE" | bash "$SCRIPT")"
AGAIN="$(printf '%s' "$WITH_FOOTER" | bash "$SCRIPT")"
[ "$AGAIN" = "$WITH_FOOTER" ]           || fail "idempotency: output changed on second pass"
[ "$(marker_count "$AGAIN")" = "1" ]    || fail "idempotency: marker count != 1"

# 4. Rogue <sub> line, attribution ON: stripped, replaced by exactly one canonical footer.
OUT="$(printf '%s' "$ROGUE" | bash "$SCRIPT")"
printf '%s' "$OUT" | grep -qiF 'Prepared with assistance' && fail "on: rogue line not scrubbed"
printf '%s' "$OUT" | grep -qF 'Fixes the thing.'          || fail "on: base body lost"
[ "$(marker_count "$OUT")" = "1" ]                        || fail "on: marker count != 1"

# 5. Model wrote its own (non-canonical) Superhuman line: no double attribution.
MODEL_FOOTER="$BASE

---
Opened with Superhuman (https://github.com/gaurav0107/superhuman)."
OUT="$(printf '%s' "$MODEL_FOOTER" | bash "$SCRIPT")"
[ "$(marker_count "$OUT")" = "1" ]                                       || fail "double-attr: marker count != 1"
[ "$(printf '%s' "$OUT" | grep -cF 'github.com/gaurav0107/superhuman')" = "1" ] || fail "double-attr: url appears more than once"

# 6. Claude/AI attribution in body: stripped; only the canonical footer remains.
AI="$BASE

🤖 Generated with Claude Code
Co-authored-by: Claude <noreply@anthropic.com>"
OUT="$(printf '%s' "$AI" | bash "$SCRIPT")"
printf '%s' "$OUT" | grep -qiF 'Generated with Claude' && fail "ai: claude line not scrubbed"
printf '%s' "$OUT" | grep -qiF 'Co-authored-by'        && fail "ai: co-author trailer not scrubbed"
printf '%s' "$OUT" | grep -qiF 'noreply@anthropic.com' && fail "ai: anthropic email not scrubbed"
[ "$(marker_count "$OUT")" = "1" ]                     || fail "ai: marker count != 1"

# 7. False-positive guard: legitimate prose mentioning tools/verbs is preserved.
LEGIT='## Summary
This fixes the Claude SDK timeout.
We generated the config with make.'
OUT="$(printf '%s' "$LEGIT" | bash "$SCRIPT")"
printf '%s' "$OUT" | grep -qF 'This fixes the Claude SDK timeout.' || fail "fp: claude-sdk sentence stripped"
printf '%s' "$OUT" | grep -qF 'We generated the config with make.' || fail "fp: generated-with-make sentence stripped"
[ "$(marker_count "$OUT")" = "1" ]                                 || fail "fp: marker count != 1"

# 8. Mid-body '---' separator preserved (only trailing attribution is touched).
SECT='## Part 1
alpha

---

## Part 2
beta'
OUT="$(printf '%s' "$SECT" | bash "$SCRIPT")"
printf '%s' "$OUT" | grep -qF '## Part 1' || fail "sect: part 1 lost"
printf '%s' "$OUT" | grep -qF '## Part 2' || fail "sect: part 2 lost"
printf '%s' "$OUT" | grep -qF 'beta'      || fail "sect: content after --- lost"
# mid-body '---' plus the footer separator == 2 horizontal rules.
[ "$(printf '%s' "$OUT" | grep -cE '^-{3,}$')" = "2" ] || fail "sect: mid-body '---' not preserved"

echo "OK test_pr_body_with_attribution.sh"
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bash tests/scripts/test_pr_body_with_attribution.sh`
Expected: FAIL — the current script does not scrub, so at minimum case 2b (`disable: rogue line not scrubbed`) or 4 fails. Confirm it does not print `OK`.

- [ ] **Step 3: Rewrite the script with the scrub pass**

Replace the entire contents of `scripts/orchestrator/pr_body_with_attribution.sh` with:

```bash
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
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bash tests/scripts/test_pr_body_with_attribution.sh`
Expected: `OK test_pr_body_with_attribution.sh`

- [ ] **Step 5: Run the full script suite to confirm no regressions**

Run: `for t in tests/scripts/test_*.sh; do bash "$t" >/dev/null && echo "ok $t" || echo "FAIL $t"; done | grep -c '^ok'`
Expected: prints the full count of test files with none reported `FAIL` (visually confirm no `FAIL ` line appears).

- [ ] **Step 6: Commit**

```bash
git add scripts/orchestrator/pr_body_with_attribution.sh tests/scripts/test_pr_body_with_attribution.sh
git commit -m "feat: scrub model-authored PR-body attribution; canonical footer is authoritative"
```

---

### Task 2: Planner defense-in-depth rule

**Files:**
- Modify: `agents/planner.md`

**Interfaces:**
- Consumes: nothing at runtime. Documentation guidance for the planner agent.
- Produces: a one-line rule instructing the planner not to author attribution in the PR body (the scrub in Task 1 enforces it deterministically regardless).

- [ ] **Step 1: Locate the planner's PR-body guidance**

Run: `grep -n -i "pr_body_sections\|pr body\|PR body\|compliance\|title" agents/planner.md | head`
Expected: prints the line(s) where the planner is told to produce the PR title/body. Note the nearest such line number to place the new rule beside it.

- [ ] **Step 2: Add the rule**

In `agents/planner.md`, next to the PR-body guidance identified in Step 1, add this bullet (match the surrounding list/indent style):

```markdown
- **Never write attribution in the PR body.** Do not add disclosure,
  "generated/prepared/opened with", `Co-authored-by`, Claude/Anthropic, or
  Superhuman/AI-tool credit lines. The harness appends the canonical Superhuman
  disclosure footer itself (`SUPERHUMAN_ATTRIBUTION`, via
  `scripts/orchestrator/pr_body_with_attribution.sh`); any such line you write
  is stripped before the PR is opened.
```

- [ ] **Step 3: Verify the rule is present and references the enforcing script**

Run: `grep -n "Never write attribution in the PR body" agents/planner.md && grep -q "pr_body_with_attribution.sh" agents/planner.md && echo RULE_OK`
Expected: prints the matched line and `RULE_OK`.

- [ ] **Step 4: Commit**

```bash
git add agents/planner.md
git commit -m "docs: instruct planner not to author PR-body attribution (harness owns it)"
```

---

## Self-Review

**1. Spec coverage:**
- Fold scrub into the existing filter → Task 1 (script rewrite). ✓
- Scrub runs regardless of flag; off → scrubbed body, no footer → Task 1 script (`SCRUBBED` computed before the case; disable path prints `SCRUBBED`) + test 2a/2b. ✓
- Verb+name whole-line matching, explicit catches, case-insensitive → Task 1 `is_attr()` + Global Constraints. ✓
- Idempotency by construction (scrub strips canonical footer, re-append) → Task 1 + test 3. ✓
- No double attribution → Task 1 + test 5. ✓
- Claude/AI attribution now caught in PR body → Task 1 explicit catches + test 6. ✓
- False-positive protection (verb+name, whole-line) → test 7. ✓
- Mid-body `---` / real content preserved; only orphaned trailing rule dropped → Task 1 cleanup + test 8. ✓
- Canonical footer text/URL-source unchanged → Task 1 final `printf` + `plugin.json` resolution. ✓
- Commits untouched → Task 1 comment; no commit logic in this file. ✓
- Defense-in-depth planner rule → Task 2. ✓

**2. Placeholder scan:** No TBD/TODO/"handle edge cases"/"similar to". Full script, full test, and exact rule text are inline. ✓

**3. Type/name consistency:** CLI contract `printf '%s' "$BODY" | pr_body_with_attribution.sh` unchanged (Phase 6 caller needs no edit). Marker string `Opened with [Superhuman]` consistent between the script's footer and the tests' `marker_count`. Disabling-value set (`off|false|0|no`) consistent between script `case` and test 2a loop. `is_attr` verb/name lists match the Global Constraints verbatim. ✓
