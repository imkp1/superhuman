# Learning Substrate — Foundation (Plan 1 of 3) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the pure, unit-testable *primitives* of the learning substrate — four typed schemas, the fixed deterministic-check registry, the retrieval query, and the deterministic compliance gate — with zero changes to the live contribution loop.

**Architecture:** Everything here is a pure function over files on disk. Schemas live in `schemas/` (draft 2020-12, validated by the existing `validate_json` in `scripts/lib/state.sh`). A new script package `scripts/lessons/` holds retrieval (`select_lessons.sh`) and the deterministic gate (`check_lessons.sh`); a new shared lib `scripts/lib/lesson_checks.sh` holds the *fixed* check registry plus the canonical dedupe-key function. No agent prompt changes, no orchestration changes — so this plan cannot regress the running system. It is the foundation Plans 2 (curation + distiller + scan) and 3 (prevent + enforce + orchestrate) build on.

**Tech Stack:** Bash 3.2, `jq`, `python3` (schema validation only), plain-bash test harness under `tests/scripts/`.

**Spec:** `docs/superpowers/specs/2026-07-03-learning-substrate-design.md` (build-order steps 1–2).

## Global Constraints

Copied verbatim from the spec. Every task's requirements implicitly include this section.

- **Bash 3.2 compatible.** No `declare -A`, no `mapfile`, no `${var,,}`, no `[[ =~ ]]`. Use `grep -E`, `case`, `tr`, arrays with `+=`.
- **Script skeleton (every script):** `#!/usr/bin/env bash`; a header-comment usage line; `set -euo pipefail`; `: "${CLAUDE_PLUGIN_ROOT:?CLAUDE_PLUGIN_ROOT must be set}"`; `source "${CLAUDE_PLUGIN_ROOT}/scripts/lib/state.sh"`; a `while [ $# -gt 0 ]; do case "$1" in … esac; done` arg loop; unknown arg → `exit 2`. **Exit codes:** `0` success, `1` recoverable/negative-result (caller branches), `2` usage/abort.
- **Executable bit + invocation convention:** directly-invoked scripts under `scripts/` are committed executable (`chmod +x`, mode `755`) like the existing `scripts/scorer/*.sh` — agents call them directly in Plan 3. Sourced libs (`scripts/lib/*.sh`, e.g. `state.sh`) stay `644`. **Tests invoke scripts via `bash "$path"`** (house convention — see `tests/scripts/test_historical_blend.sh:15`, `test_record_outcome.sh:8`), so a test never depends on the executable bit.
- **Schema skeleton (every schema):** `"$schema": "https://json-schema.org/draft/2020-12/schema"`; `"$id": "https://github.com/gaurav0107/superhuman/schemas/<name>.schema.json"`; `"additionalProperties": true`; a minimal `required` list; per-property `description`; a top-level `description` that names the **Owner** (sole writer). Timestamps are `{"type":"string","format":"date-time"}`.
- **Test skeleton (every test):** `#!/usr/bin/env bash`; `set -euo pipefail`; `export CLAUDE_PLUGIN_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"`; write only under `mktemp -d`; assert with `[ … ] || { echo "FAIL …"; exit 1; }`; end with `echo "OK test_<name>.sh"`. Never touch real `~/.superhuman/`.
- **No new dependencies.** `jq`, `python3`, `git`, `gh`, `bash` only.
- **SAFETY invariants (load-bearing — the reason the substrate is safe to learn from untrusted comments):**
  - A rule card has **no** command / URL / path-outside-repo field. `rule` is descriptive prose.
  - A `kind:"deterministic"` card's `check.id` **must** be a member of the fixed registry in `scripts/lib/lesson_checks.sh`. An unknown `check.id` executes **nothing** (`run_check` fail-opens; Plan 2's `merge_cards` will force such a card to `semantic`).
  - **Enforced ≡** `status=="active"` **and** `confidence >= 0.75` **and** `scope ∈ {repo, global}`. `global-candidate` and sub-0.75 cards are advisory (never hard-block).
  - Checks **fail open**: missing context (no worktree, no commit subject) → pass, never a spurious block.
- **Commit convention:** `feat(lessons): …` / `feat(schemas): …`, message ending with the trailer:
  `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`
- **Suite green after every task:** `for t in tests/scripts/test_*.sh; do bash "$t" || echo "FAIL: $t"; done`

---

## Task 1: `rule_card` schema

**Files:**
- Create: `schemas/rule_card.schema.json`
- Test: `tests/scripts/test_schema_rule_card.sh`

**Interfaces:**
- Produces: the canonical rule-card shape consumed by every later task and plan. Fields: `id, scope, match{repo,lang,paths,dimensions}, kind, rule, check{id,args}, source, evidence, confidence, hits, repos_seen, status, created, last_confirmed`.

- [ ] **Step 1: Write the failing test**

Create `tests/scripts/test_schema_rule_card.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
export CLAUDE_PLUGIN_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
source "$CLAUDE_PLUGIN_ROOT/scripts/lib/state.sh"
SCHEMA="$CLAUDE_PLUGIN_ROOT/schemas/rule_card.schema.json"
tmpdir=$(mktemp -d)

# A well-formed deterministic repo card validates.
cat > "$tmpdir/ok.json" <<'EOF'
{
  "id": "apache-airflow-newsfragment",
  "scope": "repo",
  "match": {"repo": "apache/airflow", "lang": "python", "paths": ["airflow-core/**"], "dimensions": ["process"]},
  "kind": "deterministic",
  "rule": "Add a newsfragment under newsfragments/ for any user-facing change.",
  "check": {"id": "file_present", "args": {"glob": "newsfragments/*"}},
  "source": "comment",
  "evidence": ["PR#65685 review by vincbeck 2026-04-23"],
  "confidence": 0.8,
  "hits": 3,
  "repos_seen": ["apache/airflow"],
  "status": "active",
  "created": "2026-04-23T10:00:00Z",
  "last_confirmed": "2026-06-30T10:00:00Z"
}
EOF
validate_json "$SCHEMA" "$tmpdir/ok.json" || { echo "FAIL valid card rejected"; exit 1; }

# A well-formed semantic global card (no check) validates.
cat > "$tmpdir/ok2.json" <<'EOF'
{
  "id": "reuse-existing-util-global",
  "scope": "global",
  "match": {"lang": "python", "dimensions": ["correctness"]},
  "kind": "semantic",
  "rule": "Reuse an existing utility instead of adding a near-duplicate.",
  "source": "outcome",
  "evidence": [],
  "confidence": 0.9,
  "hits": 5,
  "repos_seen": ["a/b", "c/d", "e/f"],
  "status": "active",
  "created": "2026-05-01T00:00:00Z",
  "last_confirmed": "2026-06-01T00:00:00Z"
}
EOF
validate_json "$SCHEMA" "$tmpdir/ok2.json" || { echo "FAIL valid semantic card rejected"; exit 1; }

# Missing a required field (rule) fails.
echo '{"id":"x","scope":"repo","match":{},"kind":"semantic","source":"comment","confidence":0.5,"hits":1,"repos_seen":[],"status":"active","created":"2026-01-01T00:00:00Z","last_confirmed":"2026-01-01T00:00:00Z"}' > "$tmpdir/bad.json"
validate_json "$SCHEMA" "$tmpdir/bad.json" 2>/dev/null && { echo "FAIL card missing 'rule' accepted"; exit 1; }

echo "OK test_schema_rule_card.sh"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/scripts/test_schema_rule_card.sh`
Expected: FAIL (schema file does not exist yet — `validate_json` errors opening it).

- [ ] **Step 3: Write the schema**

Create `schemas/rule_card.schema.json`:

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "https://github.com/gaurav0107/superhuman/schemas/rule_card.schema.json",
  "title": "rule_card",
  "description": "One learned, enforceable convention. One object per line in lessons.jsonl (repo scope) or lessons_global.jsonl (global / global-candidate scope). Owner (sole writer): lesson-distiller. Retrieved by scripts/lessons/select_lessons.sh; deterministic cards enforced by scripts/lessons/check_lessons.sh, semantic cards by the scorer LLM pass. SAFETY: 'rule' is descriptive prose only — there is deliberately no command/URL/path-outside-repo field. A deterministic 'check.id' MUST be a member of the fixed registry in scripts/lib/lesson_checks.sh; an unknown check.id is forced to kind=semantic at write time and executes nothing.",
  "type": "object",
  "additionalProperties": true,
  "required": ["id", "scope", "match", "kind", "rule", "source", "confidence", "hits", "repos_seen", "status", "created", "last_confirmed"],
  "properties": {
    "id":     {"type": "string", "description": "stable slug, e.g. apache-airflow-newsfragment"},
    "scope":  {"enum": ["repo", "global-candidate", "global"], "description": "repo=this repo only; global-candidate=advisory cross-repo; global=enforced cross-repo"},
    "match": {
      "type": "object",
      "additionalProperties": true,
      "description": "gate for where the card applies; an absent sub-field is a wildcard",
      "properties": {
        "repo":       {"type": "string", "description": "owner/repo; present for scope=repo"},
        "lang":       {"type": "string"},
        "paths":      {"type": "array", "items": {"type": "string"}, "description": "glob(s); card applies only when a changed file matches one"},
        "dimensions": {"type": "array", "items": {"type": "string"}}
      }
    },
    "kind":   {"enum": ["deterministic", "semantic"], "description": "deterministic=scripted check; semantic=LLM-judged"},
    "rule":   {"type": "string", "description": "descriptive prose only — never an instruction to run anything"},
    "check": {
      "type": "object",
      "description": "present iff kind=deterministic; check.id must be in the fixed registry",
      "required": ["id"],
      "additionalProperties": true,
      "properties": {
        "id":   {"type": "string"},
        "args": {"type": "object", "additionalProperties": true}
      }
    },
    "source":     {"enum": ["comment", "outcome", "scan"]},
    "evidence":   {"type": "array", "items": {"type": "string"}, "description": "human-readable provenance, e.g. PR#/reviewer/date"},
    "confidence": {"type": "number", "minimum": 0, "maximum": 1},
    "hits":       {"type": "integer", "minimum": 0, "description": "number of independent confirmations"},
    "repos_seen": {"type": "array", "items": {"type": "string"}, "description": "distinct repos this rule was confirmed on; drives graduation"},
    "status":     {"enum": ["active", "demoted", "retired"]},
    "created":        {"type": "string", "format": "date-time"},
    "last_confirmed": {"type": "string", "format": "date-time"}
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/scripts/test_schema_rule_card.sh`
Expected: `OK test_schema_rule_card.sh`

- [ ] **Step 5: Commit**

```bash
git add schemas/rule_card.schema.json tests/scripts/test_schema_rule_card.sh
git commit -m "feat(schemas): rule_card — typed unit of the learning substrate

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: `repo_scan`, `dossier_meta`, `lesson_regression` schemas

**Files:**
- Create: `schemas/repo_scan.schema.json`, `schemas/dossier_meta.schema.json`, `schemas/lesson_regression.schema.json`
- Test: `tests/scripts/test_schema_repo_scan.sh`, `tests/scripts/test_schema_dossier_meta.sh`, `tests/scripts/test_schema_lesson_regression.sh`

**Interfaces:**
- Produces: `repo_scan.json` shape (profiler-owned, Plan 2 writer), `dossier_meta.json` shape (distiller-owned, Plan 2 writer), `lesson_regression.jsonl` line shape (distiller/scorer writers, Plans 2–3). Grouped because all three are trivial and a reviewer would accept/reject them together.

- [ ] **Step 1: Write the three failing tests**

Create `tests/scripts/test_schema_repo_scan.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
export CLAUDE_PLUGIN_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
source "$CLAUDE_PLUGIN_ROOT/scripts/lib/state.sh"
SCHEMA="$CLAUDE_PLUGIN_ROOT/schemas/repo_scan.schema.json"
tmpdir=$(mktemp -d)
cat > "$tmpdir/ok.json" <<'EOF'
{
  "repo": "apache/airflow",
  "generated_at": "2026-07-03T00:00:00Z",
  "head_sha": "deadbeef",
  "default_branch": "main",
  "languages": ["python"],
  "source_dirs": ["airflow-core/src"],
  "test_dirs": ["tests"],
  "test_name_patterns": ["test_*.py"],
  "naming": {"functions": "snake"},
  "top_symbols": [{"name": "conf", "file": "airflow/configuration.py"}]
}
EOF
validate_json "$SCHEMA" "$tmpdir/ok.json" || { echo "FAIL valid repo_scan rejected"; exit 1; }
echo '{"repo":"a/b"}' > "$tmpdir/bad.json"
validate_json "$SCHEMA" "$tmpdir/bad.json" 2>/dev/null && { echo "FAIL repo_scan missing head_sha accepted"; exit 1; }
echo "OK test_schema_repo_scan.sh"
```

Create `tests/scripts/test_schema_dossier_meta.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
export CLAUDE_PLUGIN_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
source "$CLAUDE_PLUGIN_ROOT/scripts/lib/state.sh"
SCHEMA="$CLAUDE_PLUGIN_ROOT/schemas/dossier_meta.schema.json"
tmpdir=$(mktemp -d)
cat > "$tmpdir/ok.json" <<'EOF'
{"repo":"apache/airflow","head_sha":"deadbeef","scanned_at":"2026-07-03T00:00:00Z","authored_at":"2026-07-03T00:05:00Z","scan_digest":"sha256:abc"}
EOF
validate_json "$SCHEMA" "$tmpdir/ok.json" || { echo "FAIL valid dossier_meta rejected"; exit 1; }
echo '{"repo":"a/b","head_sha":"x"}' > "$tmpdir/bad.json"
validate_json "$SCHEMA" "$tmpdir/bad.json" 2>/dev/null && { echo "FAIL dossier_meta missing timestamps accepted"; exit 1; }
echo "OK test_schema_dossier_meta.sh"
```

Create `tests/scripts/test_schema_lesson_regression.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
export CLAUDE_PLUGIN_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
source "$CLAUDE_PLUGIN_ROOT/scripts/lib/state.sh"
SCHEMA="$CLAUDE_PLUGIN_ROOT/schemas/lesson_regression.schema.json"
tmpdir=$(mktemp -d)
cat > "$tmpdir/ok.json" <<'EOF'
{"rule_id":"apache-airflow-newsfragment","repo":"apache/airflow","pr_url":"https://github.com/apache/airflow/pull/1","kind":"shipped_violation","ts":"2026-07-03T00:00:00Z"}
EOF
validate_json "$SCHEMA" "$tmpdir/ok.json" || { echo "FAIL valid regression rejected"; exit 1; }
echo '{"rule_id":"x","repo":"a/b"}' > "$tmpdir/bad.json"
validate_json "$SCHEMA" "$tmpdir/bad.json" 2>/dev/null && { echo "FAIL regression missing kind/ts accepted"; exit 1; }
echo "OK test_schema_lesson_regression.sh"
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `for t in repo_scan dossier_meta lesson_regression; do bash tests/scripts/test_schema_$t.sh; done`
Expected: FAIL (schema files absent).

- [ ] **Step 3: Write the three schemas**

Create `schemas/repo_scan.schema.json`:

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "https://github.com/gaurav0107/superhuman/schemas/repo_scan.schema.json",
  "title": "repo_scan",
  "description": "Raw structural facts about a target repo, produced by repo-profiler at profile time. Grounds the lesson-distiller's dossier authoring so it summarizes real structure instead of exploring blind. Owner (sole writer): repo-profiler.",
  "type": "object",
  "additionalProperties": true,
  "required": ["repo", "generated_at", "head_sha"],
  "properties": {
    "repo":               {"type": "string", "description": "owner/repo slug"},
    "generated_at":       {"type": "string", "format": "date-time"},
    "head_sha":           {"type": "string", "description": "repo HEAD at scan time; copied into dossier_meta.json for freshness"},
    "default_branch":     {"type": "string"},
    "languages":          {"type": "array", "items": {"type": "string"}},
    "source_dirs":        {"type": "array", "items": {"type": "string"}},
    "test_dirs":          {"type": "array", "items": {"type": "string"}},
    "test_name_patterns": {"type": "array", "items": {"type": "string"}},
    "naming":             {"type": "object", "additionalProperties": true, "description": "observed identifier styles, e.g. {\"functions\":\"snake\"}"},
    "top_symbols":        {"type": "array", "items": {"type": "object", "additionalProperties": true}, "description": "reuse-catalog seed: [{name,file}]"}
  }
}
```

Create `schemas/dossier_meta.schema.json`:

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "https://github.com/gaurav0107/superhuman/schemas/dossier_meta.schema.json",
  "title": "dossier_meta",
  "description": "Freshness metadata for the repo architectural dossier (dossier.md). Owner (sole writer): lesson-distiller. head_sha is copied from repo_scan.json; a re-scan is triggered when HEAD moves past this and the change touches structural paths.",
  "type": "object",
  "additionalProperties": true,
  "required": ["repo", "head_sha", "scanned_at", "authored_at"],
  "properties": {
    "repo":        {"type": "string"},
    "head_sha":    {"type": "string", "description": "copied from repo_scan.json at authoring time"},
    "scanned_at":  {"type": "string", "format": "date-time"},
    "authored_at": {"type": "string", "format": "date-time"},
    "scan_digest": {"type": "string"}
  }
}
```

Create `schemas/lesson_regression.schema.json`:

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "https://github.com/gaurav0107/superhuman/schemas/lesson_regression.schema.json",
  "title": "lesson_regression",
  "description": "One event per line in ~/.superhuman/global/lesson_regressions.jsonl: a known enforced rule was violated at submission (shipped_violation) or a maintainer re-raised a rule already in the store (maintainer_reraise). This is the 'same comment recurred = learning failed' alarm. Writers: lesson-distiller, merge-probability-scorer.",
  "type": "object",
  "additionalProperties": true,
  "required": ["rule_id", "repo", "kind", "ts"],
  "properties": {
    "rule_id": {"type": "string"},
    "repo":    {"type": "string"},
    "pr_url":  {"type": "string"},
    "kind":    {"enum": ["shipped_violation", "maintainer_reraise"]},
    "ts":      {"type": "string", "format": "date-time"}
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `for t in repo_scan dossier_meta lesson_regression; do bash tests/scripts/test_schema_$t.sh; done`
Expected: three `OK …` lines.

- [ ] **Step 5: Commit**

```bash
git add schemas/repo_scan.schema.json schemas/dossier_meta.schema.json schemas/lesson_regression.schema.json \
        tests/scripts/test_schema_repo_scan.sh tests/scripts/test_schema_dossier_meta.sh tests/scripts/test_schema_lesson_regression.sh
git commit -m "feat(schemas): repo_scan, dossier_meta, lesson_regression

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: Fixed check registry + canonical dedupe key (`scripts/lib/lesson_checks.sh`)

**Files:**
- Create: `scripts/lib/lesson_checks.sh`
- Test: `tests/scripts/test_lesson_checks.sh`

**Interfaces:**
- Produces (sourced by later tasks/plans):
  - `known_checks` → space-separated check ids.
  - `is_known_check <id>` → exit 0 if known, 1 otherwise. (Plan 2 `merge_cards` uses this to force unknown-check cards to `semantic`.)
  - `run_check <check_id> <args_json> <ctx_json>` → exit 0 = pass (satisfied **or** not-applicable/fail-open), 1 = violated. Never executes anything outside the registry.
  - `card_key <card_json>` → canonical dedupe key string. Deterministic cards key on `det:<check.id>:<sorted args>`; semantic cards on `sem:<normalized rule text>`. (Plan 2 `merge_cards`/`promote_lessons` use this.)
- Context JSON shape consumed by `run_check`: `{"worktree":"/abs","changed_files":["a.py"],"head_subject":"fix: x","new_identifiers":["do_thing"]}`.

- [ ] **Step 1: Write the failing test**

Create `tests/scripts/test_lesson_checks.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
export CLAUDE_PLUGIN_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
source "$CLAUDE_PLUGIN_ROOT/scripts/lib/lesson_checks.sh"
tmpdir=$(mktemp -d)

# --- is_known_check / known_checks ---
is_known_check file_present   || { echo "FAIL file_present should be known"; exit 1; }
is_known_check totally_made_up && { echo "FAIL made-up check should be unknown"; exit 1; }

# --- run_check: unknown id fail-opens (pass) ---
run_check made_up '{}' '{}' || { echo "FAIL unknown check should fail-open pass"; exit 1; }

# --- file_present ---
mkdir -p "$tmpdir/wt/newsfragments"
echo x > "$tmpdir/wt/newsfragments/123.bugfix"
ctx=$(jq -nc --arg wt "$tmpdir/wt" '{worktree:$wt,changed_files:[],head_subject:"",new_identifiers:[]}')
run_check file_present '{"glob":"newsfragments/*"}' "$ctx" || { echo "FAIL file_present should pass (file exists)"; exit 1; }
run_check file_present '{"glob":"CHANGELOG.md"}' "$ctx"    && { echo "FAIL file_present should violate (missing)"; exit 1; }
# no worktree -> fail-open pass
run_check file_present '{"glob":"whatever"}' '{"worktree":""}' || { echo "FAIL file_present should fail-open with no worktree"; exit 1; }

# --- file_in_dir (class=test) ---
ctx_ok=$(jq -nc '{changed_files:["tests/test_x.py","src/a.py"]}')
run_check file_in_dir '{"class":"test","path_glob":"tests/*"}' "$ctx_ok"  || { echo "FAIL file_in_dir should pass (test under tests/)"; exit 1; }
ctx_bad=$(jq -nc '{changed_files:["src/test_x.py"]}')
run_check file_in_dir '{"class":"test","path_glob":"tests/*"}' "$ctx_bad" && { echo "FAIL file_in_dir should violate (test outside tests/)"; exit 1; }
# no test-named files -> not applicable -> pass
ctx_none=$(jq -nc '{changed_files:["src/a.py"]}')
run_check file_in_dir '{"class":"test","path_glob":"tests/*"}' "$ctx_none" || { echo "FAIL file_in_dir should pass (no tests changed)"; exit 1; }

# --- commit_matches ---
run_check commit_matches '{"convention":"conventional"}' '{"head_subject":"fix: crash on empty input"}' || { echo "FAIL conventional should pass"; exit 1; }
run_check commit_matches '{"convention":"conventional"}' '{"head_subject":"random subject"}'            && { echo "FAIL conventional should violate"; exit 1; }
run_check commit_matches '{"convention":"freeform"}'     '{"head_subject":"anything at all"}'          || { echo "FAIL freeform should always pass"; exit 1; }
run_check commit_matches '{"convention":"conventional"}' '{"head_subject":""}'                          || { echo "FAIL empty subject should fail-open pass"; exit 1; }

# --- identifier_case ---
run_check identifier_case '{"style":"snake"}'  '{"new_identifiers":["do_thing","_helper"]}' || { echo "FAIL snake should pass"; exit 1; }
run_check identifier_case '{"style":"snake"}'  '{"new_identifiers":["doThing"]}'            && { echo "FAIL snake should violate camelCase"; exit 1; }
run_check identifier_case '{"style":"pascal"}' '{"new_identifiers":["MyClass"]}'            || { echo "FAIL pascal should pass"; exit 1; }
run_check identifier_case '{"style":"snake"}'  '{"new_identifiers":[]}'                     || { echo "FAIL no identifiers should pass"; exit 1; }

# --- card_key ---
d1=$(card_key '{"kind":"deterministic","check":{"id":"file_present","args":{"glob":"newsfragments/*"}},"rule":"a"}')
d2=$(card_key '{"kind":"deterministic","check":{"id":"file_present","args":{"glob":"newsfragments/*"}},"rule":"DIFFERENT text"}')
[ "$d1" = "$d2" ] || { echo "FAIL deterministic key should ignore rule text"; exit 1; }
s1=$(card_key '{"kind":"semantic","rule":"Reuse   the existing util."}')
s2=$(card_key '{"kind":"semantic","rule":"reuse the existing UTIL."}')
[ "$s1" = "$s2" ] || { echo "FAIL semantic key should normalize case/space: [$s1] vs [$s2]"; exit 1; }

echo "OK test_lesson_checks.sh"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/scripts/test_lesson_checks.sh`
Expected: FAIL (`scripts/lib/lesson_checks.sh` not found — `source` errors).

- [ ] **Step 3: Write the registry**

Create `scripts/lib/lesson_checks.sh`:

```bash
#!/usr/bin/env bash
# Fixed deterministic-check registry + canonical dedupe key for rule cards.
# Sourced by scripts/lessons/check_lessons.sh (run_check) and, in Plan 2,
# by merge_cards.sh / promote_lessons.sh (is_known_check, card_key).
#
# A deterministic rule card names a check via {"id":..,"args":{..}}. check.id
# MUST be one of the checks below — mined rules may only REFERENCE a check,
# never define one, keeping the executable surface fixed (SAFETY).
#
# run_check returns 0 = pass (satisfied OR not-applicable / fail-open),
# 1 = violated. Checks FAIL OPEN on missing context: a gate never blocks on
# absent data.
#
# Context JSON (assembled by check_lessons.sh):
#   {"worktree":"/abs","changed_files":["a.py"],"head_subject":"fix: x","new_identifiers":["do_thing"]}

known_checks() { echo "file_present file_in_dir commit_matches identifier_case"; }

is_known_check() {
  case " $(known_checks) " in
    *" $1 "*) return 0 ;;
    *) return 1 ;;
  esac
}

# file_present {glob}: a path matching glob exists in the post-diff worktree.
check_file_present() {
  local args="$1" ctx="$2" glob wt rel found=""
  glob=$(printf '%s' "$args" | jq -r '.glob // ""')
  wt=$(printf '%s' "$ctx" | jq -r '.worktree // ""')
  [ -n "$glob" ] || return 0
  [ -n "$wt" ] && [ -d "$wt" ] || return 0
  while IFS= read -r f; do
    rel="${f#$wt/}"
    case "$rel" in
      $glob) found=1; break ;;
    esac
  done < <(find "$wt" -type f 2>/dev/null)
  [ -n "$found" ] && return 0 || return 1
}

# file_in_dir {class, path_glob}: every changed file of `class` lives under path_glob.
# class=test uses basename heuristics; unknown class -> fail-open.
check_file_in_dir() {
  local args="$1" ctx="$2" class pg base is_test violated=""
  class=$(printf '%s' "$args" | jq -r '.class // ""')
  pg=$(printf '%s' "$args" | jq -r '.path_glob // ""')
  [ "$class" = "test" ] || return 0
  [ -n "$pg" ] || return 0
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    base=$(basename "$f")
    is_test=""
    case "$base" in
      test_*|*_test.*|*.test.*|*.spec.*|Test*.*|*Test.*|*Tests.*) is_test=1 ;;
    esac
    [ -n "$is_test" ] || continue
    case "$f" in
      $pg) : ;;
      *)   violated=1 ;;
    esac
  done < <(printf '%s' "$ctx" | jq -r '.changed_files[]? // empty')
  [ -n "$violated" ] && return 1 || return 0
}

# commit_matches {convention}: HEAD subject matches conventional|angular|freeform.
check_commit_matches() {
  local args="$1" ctx="$2" conv subj
  conv=$(printf '%s' "$args" | jq -r '.convention // "freeform"')
  subj=$(printf '%s' "$ctx" | jq -r '.head_subject // ""')
  [ -n "$subj" ] || return 0
  case "$conv" in
    conventional)
      printf '%s' "$subj" | grep -qE '^(feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert)(\([^)]+\))?!?: .+' ;;
    angular)
      printf '%s' "$subj" | grep -qE '^[a-z0-9_.-]+: .+' ;;
    *) return 0 ;;
  esac
}

# identifier_case {style}: every new identifier follows style snake|camel|pascal.
check_identifier_case() {
  local args="$1" ctx="$2" style id violated=""
  style=$(printf '%s' "$args" | jq -r '.style // ""')
  [ -n "$style" ] || return 0
  while IFS= read -r id; do
    [ -n "$id" ] || continue
    case "$style" in
      snake)  printf '%s' "$id" | grep -qE '^[a-z_][a-z0-9_]*$'  || violated=1 ;;
      camel)  printf '%s' "$id" | grep -qE '^[a-z][a-zA-Z0-9]*$'  || violated=1 ;;
      pascal) printf '%s' "$id" | grep -qE '^[A-Z][a-zA-Z0-9]*$'  || violated=1 ;;
      *) return 0 ;;
    esac
    [ -n "$violated" ] && break
  done < <(printf '%s' "$ctx" | jq -r '.new_identifiers[]? // empty')
  [ -n "$violated" ] && return 1 || return 0
}

run_check() {
  local id="$1" args="$2" ctx="$3"
  case "$id" in
    file_present)    check_file_present    "$args" "$ctx" ;;
    file_in_dir)     check_file_in_dir     "$args" "$ctx" ;;
    commit_matches)  check_commit_matches  "$args" "$ctx" ;;
    identifier_case) check_identifier_case "$args" "$ctx" ;;
    *) return 0 ;;
  esac
}

# Canonical dedupe key. Deterministic cards key on their check; semantic cards
# on normalized rule text (lowercased, whitespace-collapsed, trimmed).
card_key() {
  printf '%s' "$1" | jq -r '
    if .kind == "deterministic"
    then "det:" + (.check.id // "") + ":" + ((.check.args // {}) | tojson)
    else "sem:" + (.rule | ascii_downcase | gsub("\\s+"; " ") | gsub("^\\s+|\\s+$"; ""))
    end'
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/scripts/test_lesson_checks.sh`
Expected: `OK test_lesson_checks.sh`

- [ ] **Step 5: Commit**

```bash
git add scripts/lib/lesson_checks.sh tests/scripts/test_lesson_checks.sh
git commit -m "feat(lessons): fixed deterministic-check registry + card_key

Closed set of named checks (file_present, file_in_dir, commit_matches,
identifier_case) with fail-open semantics, plus is_known_check and the
canonical dedupe key. Mined rules may only reference a check, never define
one — the executable surface stays fixed.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: Retrieval (`scripts/lessons/select_lessons.sh`)

**Files:**
- Create: `scripts/lessons/select_lessons.sh`
- Test: `tests/scripts/test_select_lessons.sh`

**Interfaces:**
- Consumes: JSONL rule-card stores (`lessons.jsonl`, `lessons_global.jsonl`).
- Produces: `select_lessons.sh --repo OWNER/REPO [--lang L] [--changed-files FILE] [--dimensions "d1,d2"] --store FILE [--store FILE ...] [--cap N]` → a ranked, capped JSON **array** of matching cards on stdout. Ranking: enforced first, then deterministic before semantic, then confidence descending. `retired` cards are never returned. Called by the planner, builder, and scorer in Plan 3.

- [ ] **Step 1: Write the failing test**

Create `tests/scripts/test_select_lessons.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
export CLAUDE_PLUGIN_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SEL="$CLAUDE_PLUGIN_ROOT/scripts/lessons/select_lessons.sh"
tmpdir=$(mktemp -d)

repo_store="$tmpdir/lessons.jsonl"
global_store="$tmpdir/lessons_global.jsonl"

# repo card for THIS repo, enforced deterministic
cat >> "$repo_store" <<'EOF'
{"id":"news","scope":"repo","match":{"repo":"apache/airflow","lang":"python","paths":["airflow-core/**"]},"kind":"deterministic","rule":"newsfragment","check":{"id":"file_present","args":{"glob":"newsfragments/*"}},"source":"comment","evidence":[],"confidence":0.9,"hits":3,"repos_seen":["apache/airflow"],"status":"active","created":"2026-01-01T00:00:00Z","last_confirmed":"2026-06-01T00:00:00Z"}
EOF
# repo card for a DIFFERENT repo (must be excluded)
cat >> "$repo_store" <<'EOF'
{"id":"other","scope":"repo","match":{"repo":"other/repo","lang":"python"},"kind":"semantic","rule":"other repo rule","source":"comment","evidence":[],"confidence":0.9,"hits":1,"repos_seen":["other/repo"],"status":"active","created":"2026-01-01T00:00:00Z","last_confirmed":"2026-06-01T00:00:00Z"}
EOF
# retired repo card (must be excluded)
cat >> "$repo_store" <<'EOF'
{"id":"dead","scope":"repo","match":{"repo":"apache/airflow"},"kind":"semantic","rule":"retired rule","source":"comment","evidence":[],"confidence":0.9,"hits":1,"repos_seen":["apache/airflow"],"status":"retired","created":"2026-01-01T00:00:00Z","last_confirmed":"2026-01-01T00:00:00Z"}
EOF
# global semantic card, low confidence (advisory), python
cat >> "$global_store" <<'EOF'
{"id":"reuse-global","scope":"global","match":{"lang":"python"},"kind":"semantic","rule":"reuse existing util","source":"outcome","evidence":[],"confidence":0.6,"hits":2,"repos_seen":["a/b","c/d"],"status":"active","created":"2026-01-01T00:00:00Z","last_confirmed":"2026-06-01T00:00:00Z"}
EOF
# global card for a different language (must be excluded when lang=python)
cat >> "$global_store" <<'EOF'
{"id":"go-only","scope":"global","match":{"lang":"go"},"kind":"semantic","rule":"go rule","source":"outcome","evidence":[],"confidence":0.99,"hits":9,"repos_seen":["x/y","z/w"],"status":"active","created":"2026-01-01T00:00:00Z","last_confirmed":"2026-06-01T00:00:00Z"}
EOF

out=$(bash "$SEL" --repo apache/airflow --lang python --store "$repo_store" --store "$global_store")

ids=$(printf '%s' "$out" | jq -r '[.[].id] | join(",")')
# Expect exactly news + reuse-global, in that order (enforced deterministic first, then advisory).
[ "$ids" = "news,reuse-global" ] || { echo "FAIL expected 'news,reuse-global' got '$ids'"; exit 1; }

# lang filter excludes go-only; repo filter excludes other/repo; status excludes dead.
printf '%s' "$out" | jq -e 'any(.[]; .id=="go-only" or .id=="other" or .id=="dead")' >/dev/null && { echo "FAIL leaked an excluded card"; exit 1; }

# --- path-glob filter ---
echo "airflow-core/src/x.py" > "$tmpdir/changed.txt"
out2=$(bash "$SEL" --repo apache/airflow --lang python --changed-files "$tmpdir/changed.txt" --store "$repo_store" --store "$global_store")
printf '%s' "$out2" | jq -e 'any(.[]; .id=="news")' >/dev/null || { echo "FAIL news should match airflow-core path"; exit 1; }
echo "docs/readme.md" > "$tmpdir/changed2.txt"
out3=$(bash "$SEL" --repo apache/airflow --lang python --changed-files "$tmpdir/changed2.txt" --store "$repo_store" --store "$global_store")
printf '%s' "$out3" | jq -e 'any(.[]; .id=="news")' >/dev/null && { echo "FAIL news should NOT match docs/ path"; exit 1; }
# reuse-global has no match.paths -> still present regardless of changed files
printf '%s' "$out3" | jq -e 'any(.[]; .id=="reuse-global")' >/dev/null || { echo "FAIL pathless card should survive path filter"; exit 1; }

# --- cap ---
out4=$(bash "$SEL" --repo apache/airflow --lang python --cap 1 --store "$repo_store" --store "$global_store")
[ "$(printf '%s' "$out4" | jq 'length')" -eq 1 ] || { echo "FAIL cap 1 not honored"; exit 1; }
[ "$(printf '%s' "$out4" | jq -r '.[0].id')" = "news" ] || { echo "FAIL cap should keep top-ranked (news)"; exit 1; }

# --- no stores -> [] ---
out5=$(bash "$SEL" --repo apache/airflow --store "$tmpdir/nonexistent.jsonl")
[ "$out5" = "[]" ] || { echo "FAIL missing store should yield []"; exit 1; }

# --- dimension filter (regression guard: an unrequested dimension must be excluded) ---
dstore="$tmpdir/dims.jsonl"
cat > "$dstore" <<'EOF'
{"id":"proc","scope":"repo","match":{"repo":"apache/airflow","dimensions":["process"]},"kind":"semantic","rule":"p","source":"comment","evidence":[],"confidence":0.9,"hits":1,"repos_seen":["apache/airflow"],"status":"active","created":"2026-01-01T00:00:00Z","last_confirmed":"2026-06-01T00:00:00Z"}
{"id":"style","scope":"repo","match":{"repo":"apache/airflow","dimensions":["style"]},"kind":"semantic","rule":"s","source":"comment","evidence":[],"confidence":0.9,"hits":1,"repos_seen":["apache/airflow"],"status":"active","created":"2026-01-01T00:00:00Z","last_confirmed":"2026-06-01T00:00:00Z"}
EOF
outd=$(bash "$SEL" --repo apache/airflow --dimensions process --store "$dstore")
printf '%s' "$outd" | jq -e 'any(.[]; .id=="proc")'  >/dev/null || { echo "FAIL dimension filter should keep proc"; exit 1; }
printf '%s' "$outd" | jq -e 'any(.[]; .id=="style")' >/dev/null && { echo "FAIL dimension filter should drop style"; exit 1; }

echo "OK test_select_lessons.sh"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/scripts/test_select_lessons.sh`
Expected: FAIL (`select_lessons.sh` not found).

- [ ] **Step 3: Write the script**

Create `scripts/lessons/select_lessons.sh`:

```bash
#!/usr/bin/env bash
# select_lessons.sh --repo OWNER/REPO [--lang L] [--changed-files FILE]
#                   [--dimensions "d1,d2"] --store FILE [--store FILE ...] [--cap N]
# Emits a ranked, capped JSON array of rule cards matching the contribution.
# Filters: scope/repo, lang, dimensions (jq); path-glob (bash case, if
# --changed-files given). Ranking: enforced first, deterministic before
# semantic, then confidence descending. retired cards are never returned.
set -euo pipefail
: "${CLAUDE_PLUGIN_ROOT:?CLAUDE_PLUGIN_ROOT must be set}"
source "${CLAUDE_PLUGIN_ROOT}/scripts/lib/state.sh"

REPO=""; REPO_LANG=""; CHANGED=""; DIMS=""; CAP="40"; STORES=()
while [ $# -gt 0 ]; do
  case "$1" in
    --repo)          REPO="$2"; shift 2 ;;
    --lang)          REPO_LANG="$2"; shift 2 ;;
    --changed-files) CHANGED="$2"; shift 2 ;;
    --dimensions)    DIMS="$2"; shift 2 ;;
    --cap)           CAP="$2"; shift 2 ;;
    --store)         STORES+=("$2"); shift 2 ;;
    *) echo "select_lessons.sh: unknown arg: $1" >&2; exit 2 ;;
  esac
done
[ -n "$REPO" ] || { echo "--repo required" >&2; exit 2; }

EXIST=()
for s in "${STORES[@]:-}"; do
  [ -n "$s" ] && [ -f "$s" ] && EXIST+=("$s")
done
[ "${#EXIST[@]}" -eq 0 ] && { echo '[]'; exit 0; }

if [ -n "$DIMS" ]; then
  DIMS_JSON=$(printf '%s' "$DIMS" | jq -Rc 'split(",") | map(gsub("^\\s+|\\s+$"; ""))')
else
  DIMS_JSON='[]'
fi

# Stage 1 — scope/repo, lang, dimension filter; drop retired.
STAGE1=$(jq -s \
  --arg repo "$REPO" --arg lang "$REPO_LANG" --argjson dims "$DIMS_JSON" '
  map(select(
    (if .scope == "repo" then (.match.repo == $repo) else true end)
    and (if (.match.lang // null) == null or $lang == "" then true else .match.lang == $lang end)
    and (if (.match.dimensions // []) == [] or ($dims | length) == 0 then true
         else any(.match.dimensions[]; . as $d | $dims | index($d)) end)
    and (.status != "retired")
  ))
' "${EXIST[@]}" 2>/dev/null || echo '[]')

# Stage 2 — path-glob filter (only if changed files supplied).
if [ -n "$CHANGED" ] && [ -f "$CHANGED" ]; then
  CF=()
  while IFS= read -r line; do [ -n "$line" ] && CF+=("$line"); done < "$CHANGED"
  KEPT="[]"
  while IFS= read -r card; do
    [ -n "$card" ] || continue
    npaths=$(printf '%s' "$card" | jq -r '(.match.paths // []) | length')
    if [ "$npaths" -eq 0 ]; then
      KEPT=$(printf '%s' "$KEPT" | jq -c --argjson c "$card" '. + [$c]')
      continue
    fi
    matched=""
    while IFS= read -r g; do
      [ -n "$g" ] || continue
      for f in "${CF[@]:-}"; do
        case "$f" in
          $g) matched=1 ;;
        esac
        [ -n "$matched" ] && break
      done
      [ -n "$matched" ] && break
    done < <(printf '%s' "$card" | jq -r '.match.paths[]')
    [ -n "$matched" ] && KEPT=$(printf '%s' "$KEPT" | jq -c --argjson c "$card" '. + [$c]')
  done < <(printf '%s' "$STAGE1" | jq -c '.[]')
  STAGE1="$KEPT"
fi

# Stage 3 — rank (enforced / deterministic / confidence desc) and cap.
# 0.75 mirrors ENFORCE_MIN for ranking only; it does not gate here.
printf '%s' "$STAGE1" | jq -c --argjson cap "$CAP" '
  def enforced: (.status == "active" and .confidence >= 0.75 and (.scope == "repo" or .scope == "global"));
  sort_by([ (if enforced then 0 else 1 end),
            (if .kind == "deterministic" then 0 else 1 end),
            (- .confidence) ])
  | .[:$cap]
'
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/scripts/test_select_lessons.sh`
Expected: `OK test_select_lessons.sh`

- [ ] **Step 5: Commit**

```bash
chmod +x scripts/lessons/select_lessons.sh
git add scripts/lessons/select_lessons.sh tests/scripts/test_select_lessons.sh
git commit -m "feat(lessons): select_lessons.sh — match/rank/cap retrieval

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 5: Deterministic compliance gate (`scripts/lessons/check_lessons.sh`)

**Files:**
- Create: `scripts/lessons/check_lessons.sh`
- Test: `tests/scripts/test_check_lessons.sh`

**Interfaces:**
- Consumes: a JSON **array** of rule cards (typically the output of `select_lessons.sh`) via `--cards FILE`; a context JSON via `--context FILE` (`{worktree,changed_files,head_subject,new_identifiers}`).
- Produces: `check_lessons.sh --cards FILE --context FILE [--enforce-min 0.75]` →
  stdout `{"violations":[{id,rule}],"advisories":[{id,rule}],"checked":N}`;
  **exit 0** when no *enforced* rule is violated, **exit 1** when ≥1 enforced rule is violated. Semantic cards are ignored (handled by the scorer LLM pass in Plan 3). This is the builder pre-push gate and the scorer's deterministic half in Plan 3.

- [ ] **Step 1: Write the failing test**

Create `tests/scripts/test_check_lessons.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
export CLAUDE_PLUGIN_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CHK="$CLAUDE_PLUGIN_ROOT/scripts/lessons/check_lessons.sh"
tmpdir=$(mktemp -d)

# Context: worktree WITHOUT a newsfragment, subject is non-conventional.
mkdir -p "$tmpdir/wt/src"
echo x > "$tmpdir/wt/src/a.py"
cat > "$tmpdir/ctx.json" <<EOF
{"worktree":"$tmpdir/wt","changed_files":["src/a.py"],"head_subject":"did stuff","new_identifiers":[]}
EOF

# Enforced deterministic card: newsfragment required -> VIOLATED (none present).
cat > "$tmpdir/cards.json" <<'EOF'
[
 {"id":"news","scope":"repo","match":{"repo":"apache/airflow"},"kind":"deterministic","rule":"newsfragment required","check":{"id":"file_present","args":{"glob":"newsfragments/*"}},"source":"comment","evidence":[],"confidence":0.9,"hits":3,"repos_seen":["apache/airflow"],"status":"active","created":"2026-01-01T00:00:00Z","last_confirmed":"2026-06-01T00:00:00Z"},
 {"id":"cand","scope":"global-candidate","match":{},"kind":"deterministic","rule":"conventional commits","check":{"id":"commit_matches","args":{"convention":"conventional"}},"source":"outcome","evidence":[],"confidence":0.9,"hits":2,"repos_seen":["a/b","c/d"],"status":"active","created":"2026-01-01T00:00:00Z","last_confirmed":"2026-06-01T00:00:00Z"},
 {"id":"sem","scope":"repo","match":{"repo":"apache/airflow"},"kind":"semantic","rule":"reuse existing util","source":"comment","evidence":[],"confidence":0.9,"hits":1,"repos_seen":["apache/airflow"],"status":"active","created":"2026-01-01T00:00:00Z","last_confirmed":"2026-06-01T00:00:00Z"}
]
EOF

set +e
out=$(bash "$CHK" --cards "$tmpdir/cards.json" --context "$tmpdir/ctx.json"); rc=$?
set -e
[ "$rc" -eq 1 ] || { echo "FAIL expected exit 1 on enforced violation, got $rc"; exit 1; }
# 'news' is an enforced violation; 'cand' is a candidate violation (advisory); 'sem' is skipped.
printf '%s' "$out" | jq -e '.violations | any(.id=="news")'  >/dev/null || { echo "FAIL news should be a violation"; exit 1; }
printf '%s' "$out" | jq -e '.advisories | any(.id=="cand")'  >/dev/null || { echo "FAIL cand should be an advisory"; exit 1; }
printf '%s' "$out" | jq -e '.violations | any(.id=="cand")'  >/dev/null && { echo "FAIL candidate must not be an enforced violation"; exit 1; }
[ "$(printf '%s' "$out" | jq '.checked')" -eq 2 ] || { echo "FAIL should have checked 2 deterministic cards"; exit 1; }

# Now satisfy the newsfragment rule -> no enforced violation -> exit 0.
mkdir -p "$tmpdir/wt/newsfragments"
echo x > "$tmpdir/wt/newsfragments/1.bugfix"
set +e
out2=$(bash "$CHK" --cards "$tmpdir/cards.json" --context "$tmpdir/ctx.json"); rc2=$?
set -e
[ "$rc2" -eq 0 ] || { echo "FAIL expected exit 0 once newsfragment present, got $rc2"; exit 1; }
printf '%s' "$out2" | jq -e '.violations | length == 0' >/dev/null || { echo "FAIL violations should be empty"; exit 1; }

# Empty/absent cards -> pass (graceful degradation).
set +e
out3=$(bash "$CHK" --cards "$tmpdir/none.json" --context "$tmpdir/ctx.json"); rc3=$?
set -e
[ "$rc3" -eq 0 ] || { echo "FAIL missing cards file should exit 0"; exit 1; }
[ "$(printf '%s' "$out3" | jq '.checked')" -eq 0 ] || { echo "FAIL checked should be 0"; exit 1; }

echo "OK test_check_lessons.sh"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/scripts/test_check_lessons.sh`
Expected: FAIL (`check_lessons.sh` not found).

- [ ] **Step 3: Write the script**

Create `scripts/lessons/check_lessons.sh`:

```bash
#!/usr/bin/env bash
# check_lessons.sh --cards CARDS_JSON --context CTX_JSON [--enforce-min 0.75]
# Runs each DETERMINISTIC card's registry check against the diff context.
# stdout: {"violations":[{id,rule}],"advisories":[{id,rule}],"checked":N}
# exit 0 = no enforced rule violated; exit 1 = >=1 enforced rule violated.
# Enforced = status==active AND confidence>=enforce-min AND scope in {repo,global}.
# Semantic cards are ignored here (scorer LLM pass handles them).
set -euo pipefail
: "${CLAUDE_PLUGIN_ROOT:?CLAUDE_PLUGIN_ROOT must be set}"
source "${CLAUDE_PLUGIN_ROOT}/scripts/lib/state.sh"
source "${CLAUDE_PLUGIN_ROOT}/scripts/lib/lesson_checks.sh"

CARDS=""; CTX=""; EMIN="0.75"
while [ $# -gt 0 ]; do
  case "$1" in
    --cards)       CARDS="$2"; shift 2 ;;
    --context)     CTX="$2"; shift 2 ;;
    --enforce-min) EMIN="$2"; shift 2 ;;
    *) echo "check_lessons.sh: unknown arg: $1" >&2; exit 2 ;;
  esac
done
[ -n "$CTX" ] && [ -f "$CTX" ] || { echo "check_lessons.sh: --context FILE required" >&2; exit 2; }
if [ -z "$CARDS" ] || [ ! -f "$CARDS" ]; then
  echo '{"violations":[],"advisories":[],"checked":0}'
  exit 0
fi

ctx_json=$(cat "$CTX")
violations="[]"; advisories="[]"; checked=0

while IFS= read -r card; do
  [ -n "$card" ] || continue
  kind=$(printf '%s' "$card" | jq -r '.kind')
  [ "$kind" = "deterministic" ] || continue
  cid=$(printf '%s' "$card" | jq -r '.check.id // ""')
  [ -n "$cid" ] || continue
  cargs=$(printf '%s' "$card" | jq -c '.check.args // {}')
  checked=$((checked + 1))
  if run_check "$cid" "$cargs" "$ctx_json"; then
    continue
  fi
  enforced=$(printf '%s' "$card" | jq -r --argjson emin "$EMIN" \
    '(.status == "active" and .confidence >= $emin and (.scope == "repo" or .scope == "global"))')
  entry=$(printf '%s' "$card" | jq -c '{id: .id, rule: .rule}')
  if [ "$enforced" = "true" ]; then
    violations=$(printf '%s' "$violations" | jq -c --argjson e "$entry" '. + [$e]')
  else
    advisories=$(printf '%s' "$advisories" | jq -c --argjson e "$entry" '. + [$e]')
  fi
done < <(jq -c '.[]' "$CARDS")

jq -nc --argjson v "$violations" --argjson a "$advisories" --argjson c "$checked" \
  '{violations: $v, advisories: $a, checked: $c}'

[ "$(printf '%s' "$violations" | jq 'length')" -eq 0 ] && exit 0 || exit 1
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/scripts/test_check_lessons.sh`
Expected: `OK test_check_lessons.sh`

- [ ] **Step 5: Run the FULL suite and commit**

Run: `for t in tests/scripts/test_*.sh; do bash "$t" || echo "FAIL: $t"; done`
Expected: every line `OK …`, no `FAIL:` lines (existing 35 tests + 6 new remain green).

```bash
chmod +x scripts/lessons/check_lessons.sh
git add scripts/lessons/check_lessons.sh tests/scripts/test_check_lessons.sh
git commit -m "feat(lessons): check_lessons.sh — deterministic compliance gate

Enforced deterministic rules block (exit 1); candidates and sub-threshold
rules are advisory only. Graceful pass on absent cards. Builder pre-push
gate and scorer deterministic half consume this in Plan 3.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Self-Review

**1. Spec coverage (build-order steps 1–2):**
- Step 1 "Schemas + check registry" → Tasks 1, 2 (four schemas), Task 3 (registry). ✅
- Step 2 "Retrieval + deterministic gate" → Task 4 (`select_lessons.sh`), Task 5 (`check_lessons.sh`). ✅
- Deferred to later plans (correctly out of scope here): `import_sorted` check (needs the builder's live toolchain — added in Plan 3); curation scripts `merge_cards`/`promote_lessons`/`decay_lessons`/`record_regression` (Plan 2, with their sole caller the distiller); profiler scan emission and the distiller agent (Plan 2); prevent/enforce/orchestrate wiring (Plan 3).

**2. Placeholder scan:** No TBD/TODO. Every step ships complete code and an exact run command with expected output. ✅

**3. Type consistency:** `card_key`, `run_check`, `is_known_check`, `known_checks` names match between Task 3's definition and Tasks 4–5's use. The `Enforced` predicate (`status=="active" && confidence>=0.75 && scope∈{repo,global}`) is identical in `select_lessons.sh` (ranking) and `check_lessons.sh` (gating). Context JSON keys (`worktree`, `changed_files`, `head_subject`, `new_identifiers`) match between Task 3's checks and Task 5's test fixtures. Rule-card fields used in scripts all exist in the Task 1 schema. ✅

---

## Roadmap — Plans 2 and 3 (to be written after Plan 1 executes)

Plan 1's interfaces are the seam. Once they're green and committed, these follow. Titles + one-liners only here; each becomes its own full plan with TDD steps.

**Plan 2 — Curation + Producer + Scan** (spec steps 3–5). The knowledge-base *write* side and its sole owner.
- `scripts/lessons/merge_cards.sh` — dedupe-merge a candidate via `card_key`; bump `hits`/`confidence` (cap 1.0), refresh `last_confirmed`, union `evidence`/`repos_seen`; force `semantic` on unknown `check.id`.
- `scripts/lessons/promote_lessons.sh` — graduated promotion: `card_key` in ≥2 distinct repos → `global-candidate` (advisory); a candidate reaching ≥3 distinct repos → `global` (enforced). Never downgrades an existing `global`.
- `scripts/lessons/decay_lessons.sh` — lower `confidence` with age; `retire` below 0.25 or after 180 days without confirmation.
- `scripts/lessons/record_regression.sh` — append a typed line to `lesson_regressions.jsonl`.
- `repo-profiler` change — emit `repo_scan.json` (dirs, tests, naming, top symbols, `head_sha`).
- `agents/lesson-distiller.md` (NEW) — sole owner; **seed** mode (author `dossier.md` + `dossier_meta.json` + scan cards, grounded in `repo_scan.json`) and **curate** mode (mine comments/outcome → `merge_cards` → `promote_lessons` → `decay_lessons` → contradiction demotion). Register in `.claude-plugin/plugin.json` + Codex `skills/superhuman/SKILL.md`.

**Plan 3 — Prevent + Enforce + Orchestrate** (spec steps 6–8). Wire the substrate into the live loop.
- `planner` + `builder` — inject `select_lessons.sh` output + `dossier.md` as **mandatory** context; fix the builder read-path; builder pre-push runs `check_lessons.sh`.
- `import_sorted` — add to the check registry now that the builder toolchain context exists.
- `merge-probability-scorer` — **Convention-compliance cap** (deterministic via `check_lessons.sh` + a semantic LLM pass), `convention_compliance` signal, submission-time `record_regression`.
- `opensource-contributor` — sequence the distiller (seed after profiling, freshness-gated; curate at run-end + per comment round; non-fatal).
- `resolve-comments` — hand classified comments to the distiller.
- `SHARED_STATE.md`, dashboard Learning panel, `README.md`, `CHANGELOG.md`; bump both plugin manifests to **0.8.0**.

---

## Next steps

1. Execute Plan 1 (below handoff).
2. When Plan 1 is green and committed, write Plan 2 from the roadmap + the spec, then Plan 3.
