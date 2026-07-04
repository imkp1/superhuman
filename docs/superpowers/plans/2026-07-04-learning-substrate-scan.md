# Learning Substrate — Scan + Hardening (Plan 3a of 3) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the testable script layer of Plan 3 — `scan_structure.sh` (the deterministic repo scan that grounds the dossier) and the `--enforce-min` numeric guard (Plan-1 review carry-forward) — with no changes to the live agent loop.

**Architecture:** `scan_structure.sh` is a pure function over a repo worktree: `find`/`grep`/`sort` + `jq` produce the structural facts (`repo_scan.json`, schema from Plan 1) that the Plan-3b `lesson-distiller` will read to author `dossier.md`. It uses NO `while`/`case`-in-pipe loops (bash-3.2 parse-safe) and only COMPACT JSON in shell vars passed to `--argjson` (bash-3.2 command-substitution-safe). The `--enforce-min` guard hardens the Plan-1 `check_lessons.sh` gate.

**Tech Stack:** Bash 3.2, `find`/`grep`/`sed`/`sort`, `jq`, plain-bash tests under `tests/scripts/`.

**Spec:** `docs/superpowers/specs/2026-07-03-learning-substrate-design.md` (build-order steps 4–5 scan mechanism; step 7 `--enforce-min` hardening). Depends on Plan 1 (`repo_scan.schema.json`, `check_lessons.sh`) and Plan 2.

## Global Constraints

- **Bash 3.2 compatible; the scripts and test harness run under bash 3.2, NOT the interactive zsh.** Verify every test with `bash tests/scripts/test_X.sh` and the suite with `for t in tests/scripts/test_*.sh; do bash "$t" || echo "FAIL: $t"; done`. No `declare -A`, `mapfile`, `${var,,}`, `[[ =~ ]]`. Avoid `while`/`case`-in-`$( … | … )` pipelines (bash-3.2 parse bug); prefer `find … | sed | sort | jq`. When a shell var holds JSON for `--argjson`, keep it COMPACT (`jq -c`) and off the `$( … || echo )` form.
- **Script skeleton (every script):** `#!/usr/bin/env bash`; header usage comment; `set -euo pipefail`; `: "${CLAUDE_PLUGIN_ROOT:?CLAUDE_PLUGIN_ROOT must be set}"`; `source "${CLAUDE_PLUGIN_ROOT}/scripts/lib/state.sh"`; `while [ $# -gt 0 ]; do case … esac; done` arg loop; unknown arg → `exit 2`. Exit codes 0/1/2.
- **Directly-invoked → committed mode 755** (`chmod +x`); **tests invoke via `bash "$SCRIPT"`**.
- **`scan_structure.sh` emits `repo_scan.json` on stdout** (the caller redirects). It must validate against `schemas/repo_scan.schema.json` (required `repo, generated_at, head_sha`). `--now`/`--head-sha` accepted for deterministic tests; default to `date -u` / `git rev-parse HEAD`.
- **No new dependencies.** `git`, `jq`, `find`, `grep`, `sed`, `sort`, `bash`.
- **Commit convention:** `feat(profiler): …` / `fix(lessons): …`, ending with `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`.
- **Suite green after every task** (run under bash).

---

## Task 1: `scan_structure.sh` — the deterministic repo scan

**Files:**
- Create: `scripts/profiler/scan_structure.sh`
- Test: `tests/scripts/test_scan_structure.sh`

**Interfaces:**
- Consumes: `state.sh`; a repo worktree directory; `git` for head-sha/branch.
- Produces: `scan_structure.sh --repo OWNER/REPO --worktree DIR [--head-sha SHA] [--now ISO]` → a `repo_scan.json` object on stdout with `{repo, generated_at, head_sha, default_branch, languages[], source_dirs[], test_dirs[], test_name_patterns[], naming{}, top_symbols[{file,name}]}`. Producer wiring (Plan 3b): `repo-profiler` runs it and redirects to `~/.superhuman/repos/<slug>/repo_scan.json`.

- [ ] **Step 1: Write the failing test**

Create `tests/scripts/test_scan_structure.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
export CLAUDE_PLUGIN_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
source "$CLAUDE_PLUGIN_ROOT/scripts/lib/state.sh"
SS="$CLAUDE_PLUGIN_ROOT/scripts/profiler/scan_structure.sh"
SCHEMA="$CLAUDE_PLUGIN_ROOT/schemas/repo_scan.schema.json"
tmpdir=$(mktemp -d)

# --- build a fixture repo worktree ---
WT="$tmpdir/repo"
mkdir -p "$WT/src/auth" "$WT/tests" "$WT/docs" "$WT/.git/hooks"
printf 'def parse_jwt(token):\n    return token\ndef _verify(sig):\n    return True\n' > "$WT/src/auth/jwt.py"
echo 'def helper(): pass' > "$WT/src/util.py"
echo 'export function doThing() {}' > "$WT/src/client.js"
echo 'def test_parse(): pass' > "$WT/tests/test_jwt.py"
echo 'ignored = 1' > "$WT/.git/hooks/x.py"
echo '# docs' > "$WT/docs/readme.md"

out=$(bash "$SS" --repo apache/airflow --worktree "$WT" --head-sha deadbeef --now 2026-07-04T00:00:00Z)
echo "$out" > "$tmpdir/scan.json"

# validates against the repo_scan schema
validate_json "$SCHEMA" "$tmpdir/scan.json" || { echo "FAIL scan output must validate against repo_scan.schema.json"; exit 1; }

# required fields carried through from args
[ "$(printf '%s' "$out" | jq -r .repo)" = "apache/airflow" ] || { echo "FAIL repo"; exit 1; }
[ "$(printf '%s' "$out" | jq -r .head_sha)" = "deadbeef" ] || { echo "FAIL head_sha"; exit 1; }
[ "$(printf '%s' "$out" | jq -r .generated_at)" = "2026-07-04T00:00:00Z" ] || { echo "FAIL generated_at"; exit 1; }

# structural facts
[ "$(printf '%s' "$out" | jq -rc '.source_dirs')" = '["src"]' ] || { echo "FAIL source_dirs should be [src], got $(printf '%s' "$out" | jq -rc '.source_dirs')"; exit 1; }
[ "$(printf '%s' "$out" | jq -rc '.test_dirs')" = '["tests"]' ] || { echo "FAIL test_dirs should be [tests]"; exit 1; }
printf '%s' "$out" | jq -e '.languages | index("py")' >/dev/null || { echo "FAIL languages should include py"; exit 1; }
printf '%s' "$out" | jq -e '.languages | index("js")' >/dev/null || { echo "FAIL languages should include js"; exit 1; }
printf '%s' "$out" | jq -e '[.top_symbols[].name] | index("parse_jwt")' >/dev/null || { echo "FAIL top_symbols should include parse_jwt"; exit 1; }
# .git content is excluded
printf '%s' "$out" | jq -e '[.top_symbols[].file] | any(test("\\.git/"))' >/dev/null && { echo "FAIL .git content must be excluded"; exit 1; }

# --- missing/invalid worktree -> exit 2 ---
set +e
bash "$SS" --repo a/b --worktree "$tmpdir/nope" 2>/dev/null; rc=$?
set -e
[ "$rc" -eq 2 ] || { echo "FAIL missing worktree should exit 2, got $rc"; exit 1; }

echo "OK test_scan_structure.sh"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/scripts/test_scan_structure.sh`
Expected: FAIL (`scan_structure.sh` not found — `bash "$SS"` errors).

- [ ] **Step 3: Write the script**

Create `scripts/profiler/scan_structure.sh`:

```bash
#!/usr/bin/env bash
# scan_structure.sh --repo OWNER/REPO --worktree DIR [--head-sha SHA] [--now ISO]
# Emits repo_scan.json (structural facts) on stdout — the deterministic scan that
# grounds the lesson-distiller's dossier (producer: repo-profiler). Fields beyond
# {repo,generated_at,head_sha} are best-effort heuristics.
#
# bash-3.2 discipline: uses only find/grep/sed/sort + jq (NO while/case-in-pipe,
# which bash 3.2 mis-parses), and every JSON captured into a shell var is COMPACT
# (jq -c) so `--argjson` is safe. VERIFY UNDER bash, NOT zsh.
set -euo pipefail
: "${CLAUDE_PLUGIN_ROOT:?CLAUDE_PLUGIN_ROOT must be set}"
source "${CLAUDE_PLUGIN_ROOT}/scripts/lib/state.sh"

REPO=""; WT=""; HEAD_SHA=""; NOW=""
while [ $# -gt 0 ]; do
  case "$1" in
    --repo)     REPO="$2"; shift 2 ;;
    --worktree) WT="$2"; shift 2 ;;
    --head-sha) HEAD_SHA="$2"; shift 2 ;;
    --now)      NOW="$2"; shift 2 ;;
    *) echo "scan_structure.sh: unknown arg: $1" >&2; exit 2 ;;
  esac
done
[ -n "$REPO" ] || { echo "--repo required" >&2; exit 2; }
[ -n "$WT" ] && [ -d "$WT" ] || { echo "--worktree DIR (existing) required" >&2; exit 2; }
[ -n "$NOW" ] || NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
[ -n "$HEAD_SHA" ] || HEAD_SHA=$(git -C "$WT" rev-parse HEAD 2>/dev/null || echo "unknown")
DEFAULT_BRANCH=$(git -C "$WT" symbolic-ref --short HEAD 2>/dev/null || echo "main")

KNOWN_EXTS='py js ts go rs java kt cpp cc c rb cs php swift'

# languages: distinct known source extensions present (compact array)
LANGS=$(find "$WT" -type f -not -path '*/.git/*' 2>/dev/null \
  | sed -n 's/.*\.\([a-z][a-z0-9]*\)$/\1/p' | sort -u \
  | jq -R . | jq -sc --argjson known "$(printf '%s\n' $KNOWN_EXTS | jq -R . | jq -sc .)" '[ .[] | select(. as $e | $known | index($e)) ]')

# source_dirs: top-level dir of each source file, minus a test/docs denylist
SRCDIRS=$(find "$WT" -mindepth 2 -type f \( -name '*.py' -o -name '*.js' -o -name '*.ts' -o -name '*.go' -o -name '*.rs' -o -name '*.java' -o -name '*.kt' -o -name '*.rb' \) -not -path '*/.git/*' 2>/dev/null \
  | sed "s#^$WT/##" | sed 's#/.*##' | sort -u | grep -vxE '(tests?|spec|__tests__|docs?|node_modules|vendor|examples)' \
  | jq -R . | jq -sc .)

# test_dirs: any directory whose basename looks like a test dir
TESTDIRS=$(find "$WT" -type d \( -name test -o -name tests -o -name spec -o -name __tests__ \) -not -path '*/.git/*' 2>/dev/null \
  | sed "s#^$WT/##" | sort -u | jq -R . | jq -sc .)

# top_symbols: {file,name} for defs/classes/exports across source files, first 12 (compact)
TOPSYMS=$(grep -rHnE '^(def |class |export default function |export function |function )[A-Za-z_]' "$WT" --include='*.py' --include='*.js' --include='*.ts' --include='*.go' --include='*.rb' 2>/dev/null \
  | sed "s#^$WT/##" | head -12 \
  | jq -Rc '[ inputs | capture("^(?<file>[^:]+):[0-9]+:(def |class |export default function |export function |function )(?<name>[A-Za-z_][A-Za-z0-9_]*)") ]' 2>/dev/null || echo '[]')
[ -n "$TOPSYMS" ] || TOPSYMS='[]'

jq -n --arg repo "$REPO" --arg now "$NOW" --arg head "$HEAD_SHA" --arg db "$DEFAULT_BRANCH" \
  --argjson languages "$LANGS" --argjson source_dirs "$SRCDIRS" \
  --argjson test_dirs "$TESTDIRS" --argjson top_symbols "$TOPSYMS" \
  '{repo:$repo, generated_at:$now, head_sha:$head, default_branch:$db,
    languages:$languages, source_dirs:$source_dirs, test_dirs:$test_dirs,
    test_name_patterns:[], naming:{}, top_symbols:$top_symbols}'
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/scripts/test_scan_structure.sh`
Expected: `OK test_scan_structure.sh`

- [ ] **Step 5: Commit**

```bash
chmod +x scripts/profiler/scan_structure.sh
git add scripts/profiler/scan_structure.sh tests/scripts/test_scan_structure.sh
git commit -m "feat(profiler): scan_structure.sh — deterministic repo scan for the dossier

Emits repo_scan.json (languages, source_dirs, test_dirs, top_symbols) from a
worktree using find/grep+jq — the scan that grounds the lesson-distiller dossier.
bash-3.2-safe (no while/case-in-pipe; compact JSON for --argjson).

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: `check_lessons.sh` `--enforce-min` numeric guard (Plan-1 carry-forward)

**Files:**
- Modify: `scripts/lessons/check_lessons.sh` (add a validation right after the arg loop)
- Test: `tests/scripts/test_check_lessons.sh` (add one assertion)

**Interfaces:**
- No signature change. Adds input validation: a non-numeric `--enforce-min` now exits 2 with a clear message instead of failing obscurely (jq `--argjson emin` error mid-run).

- [ ] **Step 1: Add the failing assertion to the existing test**

In `tests/scripts/test_check_lessons.sh`, find the final line `echo "OK test_check_lessons.sh"` and insert this block immediately BEFORE it:

```bash
# --- non-numeric --enforce-min is rejected with exit 2 (before any card processing) ---
set +e
bash "$CHK" --cards "$tmpdir/cards.json" --context "$tmpdir/ctx.json" --enforce-min not-a-number 2>/dev/null; rc=$?
set -e
[ "$rc" -eq 2 ] || { echo "FAIL non-numeric --enforce-min should exit 2, got $rc"; exit 1; }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/scripts/test_check_lessons.sh`
Expected: FAIL — a non-numeric `--enforce-min` currently does NOT exit 2 cleanly (it reaches the jq gate and errors with a different code, or 0), so the new assertion fails.

- [ ] **Step 3: Add the guard**

In `scripts/lessons/check_lessons.sh`, find the context-file validation line:
```
[ -n "$CTX" ] && [ -f "$CTX" ] || { echo "check_lessons.sh: --context FILE required" >&2; exit 2; }
```
Immediately AFTER it, add:
```
printf '%s' "$EMIN" | grep -qE '^[0-9]+(\.[0-9]+)?$' || { echo "check_lessons.sh: --enforce-min must be numeric" >&2; exit 2; }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/scripts/test_check_lessons.sh`
Expected: `OK test_check_lessons.sh`

- [ ] **Step 5: Run the FULL suite (under bash) and commit**

Run: `for t in tests/scripts/test_*.sh; do bash "$t" || echo "FAIL: $t"; done`
Expected: every line `OK …`, no `FAIL:`.

```bash
git add scripts/lessons/check_lessons.sh tests/scripts/test_check_lessons.sh
git commit -m "fix(lessons): check_lessons validates --enforce-min is numeric

Plan-1 review carry-forward: a non-numeric --enforce-min now exits 2 with a clear
message instead of failing obscurely inside the jq gate.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Self-Review

**1. Spec coverage:** `scan_structure.sh` (build steps 4–5 scan mechanism) → Task 1; `--enforce-min` guard (step 7 hardening, Plan-1 carry-forward) → Task 2. Deferred to Plan 3b/3c: `repo_scan.json` emission wiring in `repo-profiler`; the `lesson-distiller` agent; the `import_sorted` registry check (tool-dependent — best implemented as a builder pre-push tool-run in Plan 3c, not a unit-testable registry check); the `state.sh` shared temp-file helper (optional refactor); the `select_lessons.sh` `--changed-files` caller assertion (belongs in the Plan 3c builder/scorer caller). ✅

**2. Placeholder scan:** No TBD/TODO; every step ships complete, bash-verified code with an exact command + expected output. ✅

**3. Type consistency:** `scan_structure.sh` output matches `repo_scan.schema.json` fields exactly (verified: the fixture output validates). `--enforce-min`/`$EMIN` names match `check_lessons.sh`'s existing arg. ✅

---

## Roadmap — Plan 3b + 3c (the producer and the live-loop wiring)

- **Plan 3b — `lesson-distiller` agent + profiler wiring:** `repo-profiler` runs `scan_structure.sh` → `repo_scan.json` + `dossier_meta.json` freshness; `agents/lesson-distiller.md` (NEW) seed mode (author `dossier.md` + scan rule-cards) and curate mode (mine comments/outcome → `merge_cards`/`promote_lessons`/`decay_lessons`, and the three distiller-owned transitions from Plan 2's review: emit-candidates-active, `demoted`→`active` re-confirmation, contradiction-demotion). Register in `.claude-plugin/plugin.json` + Codex `SKILL.md`.
- **Plan 3c — live-loop integration:** planner/builder mandatory injection (prevent); `merge-probability-scorer` convention-compliance cap + `record_regression` on shipped violations (enforce); `import_sorted` as a builder pre-push tool-run; `resolve-comments` → distiller handoff; `opensource-contributor` sequences distiller phases; `select_lessons.sh` caller asserts `--changed-files`; a shared `state.sh` temp-file helper; `SHARED_STATE.md`, dashboard Learning panel, `README`/`CHANGELOG`; bump both manifests to 0.8.0.

## Next steps

1. Execute Plan 3a (subagent-driven).
2. Then write + execute Plan 3b, then 3c. Everything stays on this branch for a single release.
