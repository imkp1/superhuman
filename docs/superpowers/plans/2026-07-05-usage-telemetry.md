# Usage Telemetry (Adoption Analytics) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Report two basic adoption metrics — invocation count and PRs-raised count, keyed by GitHub username — to a PostHog project the maintainer owns, opt-out, without ever blocking or failing a contribution run.

**Architecture:** A single new best-effort script `scripts/lib/usage_ping.sh` builds one PostHog event (`superhuman_run`) and sends it via a bounded `curl`. It's called from the existing single terminal hook `scripts/orchestrator/write_run_summary.sh`, which backgrounds the call so the run never waits. Opt-out is honored via a `SUPERHUMAN_`-namespaced env var and a persistent flag file. The GitHub username is cached to `identity.json` by Phase 0 of the orchestrator.

**Tech Stack:** Bash, `jq`, `curl`, PostHog cloud (US) capture endpoint. Tests are plain-bash in the existing `tests/scripts/` style (stub `curl`/`gh` on `PATH`, isolated `HOME`).

## Global Constraints

- **Opt-out, on by default.** Telemetry sends unless explicitly disabled.
- **Never block or fail the caller.** `usage_ping.sh` exits 0 on every path; `curl` is bounded to `--max-time 3` and its failure is swallowed; the caller backgrounds the call.
- **All env vars `SUPERHUMAN_`-prefixed.** `SUPERHUMAN_TELEMETRY` (`off`|`print`), `SUPERHUMAN_POSTHOG_KEY`, `SUPERHUMAN_POSTHOG_HOST`. `DO_NOT_TRACK` is intentionally NOT honored.
- **PostHog:** US cloud, default host `https://us.i.posthog.com`, default public project key `phc_C8PYp2Sjq6pfQQ8u6f3r37rqdQYnXNVgJEJGQYrDMm8y` (write-only ingestion key; safe to embed).
- **Event schema:** exactly one event `superhuman_run` per terminal run. Properties: `pr_raised` (bool), `outcome` (string), `version` (string). Nothing else — no repo/issue/diff/path data.
- **Metrics derived in PostHog:** invocations = count of `superhuman_run`; PRs raised = count where `pr_raised=true`; adopters = unique `distinct_id`.
- **Scripts require `CLAUDE_PLUGIN_ROOT`** (matches every existing script under `scripts/`).
- **Refinement over spec:** the spec described a backgrounded curl *inside* `usage_ping.sh`. For testability the send is now *synchronous inside* the script (bounded `curl --max-time 3`) and the *caller* backgrounds the whole invocation. Same non-blocking guarantee. The first-run notice writes to `/dev/tty` (fallback stderr) so it survives the caller's `>/dev/null 2>&1`.

---

### Task 1: `usage_ping.sh` — event emitter with opt-out gate

**Files:**
- Create: `scripts/lib/usage_ping.sh`
- Test: `tests/scripts/test_usage_ping.sh`

**Interfaces:**
- Consumes: `CLAUDE_PLUGIN_ROOT` env (to read `.claude-plugin/plugin.json`), `$HOME/.superhuman/global/{telemetry.json,identity.json}`, env `SUPERHUMAN_TELEMETRY`, `SUPERHUMAN_POSTHOG_KEY`, `SUPERHUMAN_POSTHOG_HOST`.
- Produces: CLI `usage_ping.sh --pr-url <URL|""> --outcome <STRING>`. Side effects: may create `telemetry.json` (first run) and `identity.json` (username cache); sends a `superhuman_run` event to PostHog. Always exits 0.

- [ ] **Step 1: Write the failing test**

Create `tests/scripts/test_usage_ping.sh`:

```bash
#!/usr/bin/env bash
# tests/scripts/test_usage_ping.sh
set -uo pipefail
export CLAUDE_PLUGIN_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT="$CLAUDE_PLUGIN_ROOT/scripts/lib/usage_ping.sh"

fail() { echo "FAIL: $1"; exit 1; }

setup() {
  TMP=$(mktemp -d)
  export HOME="$TMP/home"
  mkdir -p "$HOME/.superhuman/global"
  BIN="$TMP/bin"; mkdir -p "$BIN"
  export CURL_LOG="$TMP/curl.log"; : > "$CURL_LOG"
  cat > "$BIN/curl" <<'EOF'
#!/usr/bin/env bash
echo "$@" >> "$CURL_LOG"
EOF
  cat > "$BIN/gh" <<'EOF'
#!/usr/bin/env bash
[ -n "${GH_FAIL:-}" ] && exit 1
echo "octocat"
EOF
  chmod +x "$BIN/curl" "$BIN/gh"
  export PATH="$BIN:$PATH"
  unset SUPERHUMAN_TELEMETRY GH_FAIL
}
teardown() { rm -rf "$TMP"; }

enable() { printf '{"enabled":true}\n'  > "$HOME/.superhuman/global/telemetry.json"; }
ident()  { printf '{"github_username":"octocat"}\n' > "$HOME/.superhuman/global/identity.json"; }

# 1. env opt-out -> no send
setup
SUPERHUMAN_TELEMETRY=off bash "$SCRIPT" --pr-url "http://x" --outcome ok
[ -s "$CURL_LOG" ] && fail "env off should not send"
teardown

# 2. flag opt-out -> no send
setup
printf '{"enabled":false}\n' > "$HOME/.superhuman/global/telemetry.json"
bash "$SCRIPT" --pr-url "http://x" --outcome ok
[ -s "$CURL_LOG" ] && fail "flag disabled should not send"
teardown

# 3. enabled + PR -> send with pr_raised true
setup; enable; ident
bash "$SCRIPT" --pr-url "http://x/pull/1" --outcome merged_ready
grep -q 'superhuman_run'    "$CURL_LOG" || fail "missing event name"
grep -q 'octocat'           "$CURL_LOG" || fail "missing distinct_id"
grep -q '"pr_raised":true'  "$CURL_LOG" || fail "missing pr_raised true"
teardown

# 3b. enabled, no PR -> pr_raised false
setup; enable; ident
bash "$SCRIPT" --pr-url "" --outcome no_pr
grep -q '"pr_raised":false' "$CURL_LOG" || fail "missing pr_raised false"
teardown

# 4. print mode -> payload on stderr, no send
setup; enable; ident
out=$(SUPERHUMAN_TELEMETRY=print bash "$SCRIPT" --pr-url "http://x" --outcome ok 2>&1 >/dev/null)
echo "$out" | grep -q 'superhuman_run' || fail "print mode should emit payload"
[ -s "$CURL_LOG" ] && fail "print mode should not send"
teardown

# 5. unknown user fallback
setup; enable
export GH_FAIL=1
bash "$SCRIPT" --pr-url "" --outcome ok
grep -q 'unknown' "$CURL_LOG" || fail "should fall back to unknown distinct_id"
teardown

# 6. first run creates flag file
setup
bash "$SCRIPT" --pr-url "" --outcome ok 2>/dev/null
[ -f "$HOME/.superhuman/global/telemetry.json" ] || fail "first run should create flag file"
teardown

echo "OK test_usage_ping.sh"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/scripts/test_usage_ping.sh`
Expected: FAIL (script does not exist yet) — e.g. `No such file or directory` / a `FAIL:` line, non-zero exit.

- [ ] **Step 3: Write minimal implementation**

Create `scripts/lib/usage_ping.sh`:

```bash
#!/usr/bin/env bash
# usage_ping.sh --pr-url <URL|""> --outcome <STRING>
# Best-effort adoption telemetry. Sends one 'superhuman_run' event to PostHog.
# MUST never block or fail the caller: exits 0 on every path, curl is bounded.
set -uo pipefail

POSTHOG_KEY="${SUPERHUMAN_POSTHOG_KEY:-phc_C8PYp2Sjq6pfQQ8u6f3r37rqdQYnXNVgJEJGQYrDMm8y}"
POSTHOG_HOST="${SUPERHUMAN_POSTHOG_HOST:-https://us.i.posthog.com}"
GLOBAL_DIR="$HOME/.superhuman/global"
FLAG_FILE="$GLOBAL_DIR/telemetry.json"
IDENTITY_FILE="$GLOBAL_DIR/identity.json"

PR_URL=""; OUTCOME=""
while [ $# -gt 0 ]; do
  case "$1" in
    --pr-url)  PR_URL="${2:-}"; shift 2 ;;
    --outcome) OUTCOME="${2:-}"; shift 2 ;;
    *) shift ;;   # ignore unknown args; telemetry must never hard-fail
  esac
done

# 1. Env opt-out (highest precedence).
[ "${SUPERHUMAN_TELEMETRY:-}" = "off" ] && exit 0

# 2. First-run notice + persistent flag (notice via /dev/tty so it survives a
#    backgrounded/redirected caller; falls back to stderr where no tty).
if [ ! -f "$FLAG_FILE" ]; then
  mkdir -p "$GLOBAL_DIR"
  msg="superhuman records anonymous usage counts (your GitHub username, run count, PR count) to help the maintainer measure adoption. Disable with SUPERHUMAN_TELEMETRY=off — see TELEMETRY.md."
  { echo "$msg" > /dev/tty; } 2>/dev/null || echo "$msg" >&2
  printf '{"enabled":true}\n' > "$FLAG_FILE"
fi

# 3. Persistent flag opt-out.
enabled=$(jq -r '.enabled // true' "$FLAG_FILE" 2>/dev/null || echo true)
[ "$enabled" = "false" ] && exit 0

# 4. Resolve GitHub username (cache -> gh -> "unknown").
username=""
if [ -f "$IDENTITY_FILE" ]; then
  username=$(jq -r '.github_username // empty' "$IDENTITY_FILE" 2>/dev/null || echo "")
fi
if [ -z "$username" ] && command -v gh >/dev/null 2>&1; then
  username=$(gh api user --jq '.login' 2>/dev/null || echo "")
  if [ -n "$username" ]; then
    mkdir -p "$GLOBAL_DIR"
    printf '{"github_username":"%s"}\n' "$username" > "$IDENTITY_FILE"
  fi
fi
[ -z "$username" ] && username="unknown"

# 5. Plugin version.
version=$(jq -r '.version // "unknown"' \
  "${CLAUDE_PLUGIN_ROOT:-}/.claude-plugin/plugin.json" 2>/dev/null || echo "unknown")

# 6. pr_raised.
if [ -n "$PR_URL" ]; then pr_raised=true; else pr_raised=false; fi

# 7. Build payload.
payload=$(jq -nc \
  --arg key "$POSTHOG_KEY" --arg uid "$username" \
  --arg out "$OUTCOME" --arg ver "$version" \
  --argjson pr "$pr_raised" \
  '{api_key:$key, event:"superhuman_run", distinct_id:$uid,
    properties:{pr_raised:$pr, outcome:$out, version:$ver}}' 2>/dev/null) || exit 0

# 8. Print mode (transparency / dry-run).
if [ "${SUPERHUMAN_TELEMETRY:-}" = "print" ]; then
  echo "$payload" >&2
  exit 0
fi

# 9. Send: bounded, silent, never fails the caller.
curl -sf --max-time 3 -X POST \
  -H 'Content-Type: application/json' \
  -d "$payload" \
  "$POSTHOG_HOST/i/v0/e/" >/dev/null 2>&1 || true

exit 0
```

- [ ] **Step 4: Make the script executable and run the test to verify it passes**

Run: `chmod +x scripts/lib/usage_ping.sh && bash tests/scripts/test_usage_ping.sh`
Expected: `OK test_usage_ping.sh`

- [ ] **Step 5: Commit**

```bash
git add scripts/lib/usage_ping.sh tests/scripts/test_usage_ping.sh
git commit -m "feat: add usage_ping.sh adoption telemetry emitter (opt-out)"
```

---

### Task 2: `telemetry_optout.sh` — persistent enable/disable helper

**Files:**
- Create: `scripts/lib/telemetry_optout.sh`
- Test: `tests/scripts/test_telemetry_optout.sh`

**Interfaces:**
- Consumes: `$HOME`.
- Produces: CLI `telemetry_optout.sh [--on]`. Writes `$HOME/.superhuman/global/telemetry.json` = `{"enabled":false}` (default) or `{"enabled":true}` (`--on`). This is the same `telemetry.json` `usage_ping.sh` (Task 1) reads at step 3.

- [ ] **Step 1: Write the failing test**

Create `tests/scripts/test_telemetry_optout.sh`:

```bash
#!/usr/bin/env bash
# tests/scripts/test_telemetry_optout.sh
set -euo pipefail
export CLAUDE_PLUGIN_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT="$CLAUDE_PLUGIN_ROOT/scripts/lib/telemetry_optout.sh"
TMP=$(mktemp -d); export HOME="$TMP"

bash "$SCRIPT"
grep -q '"enabled":false' "$HOME/.superhuman/global/telemetry.json" \
  || { echo "FAIL: default should disable"; exit 1; }

bash "$SCRIPT" --on
grep -q '"enabled":true' "$HOME/.superhuman/global/telemetry.json" \
  || { echo "FAIL: --on should enable"; exit 1; }

rm -rf "$TMP"
echo "OK test_telemetry_optout.sh"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/scripts/test_telemetry_optout.sh`
Expected: FAIL — script does not exist (`No such file or directory`), non-zero exit.

- [ ] **Step 3: Write minimal implementation**

Create `scripts/lib/telemetry_optout.sh`:

```bash
#!/usr/bin/env bash
# telemetry_optout.sh [--on]
# Persistently disable (default) or re-enable superhuman adoption telemetry
# by writing the enabled flag that usage_ping.sh honors.
set -euo pipefail
GLOBAL_DIR="$HOME/.superhuman/global"
FLAG_FILE="$GLOBAL_DIR/telemetry.json"
mkdir -p "$GLOBAL_DIR"
if [ "${1:-}" = "--on" ]; then
  printf '{"enabled":true}\n' > "$FLAG_FILE"
  echo "superhuman telemetry: enabled"
else
  printf '{"enabled":false}\n' > "$FLAG_FILE"
  echo "superhuman telemetry: disabled"
fi
```

- [ ] **Step 4: Make executable and run the test to verify it passes**

Run: `chmod +x scripts/lib/telemetry_optout.sh && bash tests/scripts/test_telemetry_optout.sh`
Expected: `OK test_telemetry_optout.sh`

- [ ] **Step 5: Commit**

```bash
git add scripts/lib/telemetry_optout.sh tests/scripts/test_telemetry_optout.sh
git commit -m "feat: add telemetry_optout.sh persistent enable/disable helper"
```

---

### Task 3: Wire telemetry into the terminal hook + cache identity

**Files:**
- Modify: `scripts/orchestrator/write_run_summary.sh:32` (append after the `atomic_write_json` call)
- Modify: `agents/opensource-contributor.md:129` (Phase 0 — add identity cache after the `commit.template` unset line)
- Test: `tests/scripts/test_write_run_summary.sh` (extend existing)

**Interfaces:**
- Consumes: `usage_ping.sh` CLI from Task 1 (`--pr-url`, `--outcome`).
- Produces: on every terminal state, a backgrounded best-effort telemetry call; `identity.json` written by Phase 0 for `usage_ping.sh` to read.

- [ ] **Step 1: Make the existing test hermetic against telemetry**

The existing `tests/scripts/test_write_run_summary.sh` calls `write_run_summary.sh` twice with inline `HOME="$tmpdir"` and `set -euo pipefail`. Once telemetry is wired (Step 3), each call fires a backgrounded `usage_ping.sh`. Keep the test off the network by disabling telemetry for the whole test: add this line immediately after the existing `export CLAUDE_PLUGIN_ROOT=...` line (near the top):

```bash
export SUPERHUMAN_TELEMETRY=off   # keep telemetry wiring from hitting the network in tests
```

Then append this assertion block just before the final `echo "OK test_write_run_summary.sh"` line (reuses the existing `tmpdir` variable and inline-`HOME` style already in the file):

```bash
# --- telemetry wiring: run_summary is still written and exit stays clean ---
HOME="$tmpdir" bash "$CLAUDE_PLUGIN_ROOT/scripts/orchestrator/write_run_summary.sh" \
  --repo o/r --outcome merged_ready --iterations 2 \
  --pr-url https://github.com/o/r/pull/1 \
  --completed-at 2026-07-05T00:00:00Z --exit-reason done
jq -e '.outcome=="merged_ready"' "$tmpdir/.superhuman/repos/o-r/run_summary.json" >/dev/null \
  || { echo "FAIL: telemetry wiring broke run_summary"; exit 1; }
```

- [ ] **Step 2: Run the extended test to verify it fails**

Run: `bash tests/scripts/test_write_run_summary.sh`
Expected: FAIL — `write_run_summary.sh` does not yet invoke `usage_ping.sh`, so either the new block errors or (once you add a broken call) the summary check fails. Confirm it does not print `OK`.

- [ ] **Step 3: Add the telemetry call to `write_run_summary.sh`**

The script currently ends at line 32 with:

```bash
atomic_write_json "$dir/run_summary.json" "$content"
```

Append after that line:

```bash

# Best-effort adoption telemetry (opt-out). Backgrounded + fully swallowed so it
# can never block or fail the run. See scripts/lib/usage_ping.sh and TELEMETRY.md.
"${CLAUDE_PLUGIN_ROOT}/scripts/lib/usage_ping.sh" \
  --pr-url "$PR" --outcome "$OUT" >/dev/null 2>&1 & disown 2>/dev/null || true
```

- [ ] **Step 4: Add the identity-cache line to Phase 0 of the orchestrator**

In `agents/opensource-contributor.md`, Phase 0's git-identity block currently ends (line ~129) with:

```bash
   git -C "$WORKDIR" config --unset-all commit.template 2>/dev/null || true
```

Immediately after that line, inside the same fenced code block, add:

```bash
   # Cache identity for best-effort adoption telemetry (see TELEMETRY.md).
   mkdir -p "$HOME/.superhuman/global"
   printf '{"github_username":"%s"}\n' "$GH_USER" \
     > "$HOME/.superhuman/global/identity.json"
```

- [ ] **Step 5: Run the extended test to verify it passes**

Run: `bash tests/scripts/test_write_run_summary.sh`
Expected: `OK test_write_run_summary.sh`

- [ ] **Step 6: Commit**

```bash
git add scripts/orchestrator/write_run_summary.sh agents/opensource-contributor.md tests/scripts/test_write_run_summary.sh
git commit -m "feat: emit adoption telemetry from terminal hook; cache gh identity in Phase 0"
```

---

### Task 4: Documentation — `TELEMETRY.md` + pointers

**Files:**
- Create: `TELEMETRY.md`
- Modify: `README.md` (add a short "Telemetry" pointer)
- Modify: `SECURITY.md` (add a short "Telemetry" pointer)

**Interfaces:**
- Consumes: nothing at runtime. This is the canonical disclosure the first-run notice references.
- Produces: user-facing documentation of what is sent and every opt-out path.

- [ ] **Step 1: Create `TELEMETRY.md`**

```markdown
# Telemetry

superhuman collects **basic, opt-out** usage telemetry so the maintainer can
measure adoption and prioritize improvements. It is deliberately minimal.

## What is sent

Exactly one event, `superhuman_run`, when a contribution run reaches any
terminal state:

| Field | Example | Meaning |
|---|---|---|
| `distinct_id` | `octocat` | your GitHub username (from `gh api user`) |
| `pr_raised` | `true` | whether the run opened a pull request |
| `outcome` | `merged_ready` | the run's terminal outcome |
| `version` | `0.8.0` | plugin version |

**Nothing else.** No repository names, issue numbers, diffs, file contents,
scores, or local paths ever leave your machine. Detailed metrics stay local in
`~/.superhuman/`.

Metrics the maintainer derives: total invocations (event count), PRs raised
(events where `pr_raised=true`), and unique adopters (unique `distinct_id`).

## Where it goes

A PostHog project (US cloud) owned by the maintainer. The embedded key is a
**write-only ingestion key** — it can only append events, never read data.

## See exactly what would be sent

```bash
SUPERHUMAN_TELEMETRY=print <run superhuman normally>
```

Print mode emits the literal JSON payload to stderr and sends nothing.

## How to opt out

Any one of these disables telemetry:

- **This session:** `export SUPERHUMAN_TELEMETRY=off`
- **Permanently:** `scripts/lib/telemetry_optout.sh`
  (re-enable with `scripts/lib/telemetry_optout.sh --on`)
- **By hand:** write `{"enabled":false}` to `~/.superhuman/global/telemetry.json`

## Overrides

- `SUPERHUMAN_POSTHOG_KEY` — send to a different PostHog project.
- `SUPERHUMAN_POSTHOG_HOST` — default `https://us.i.posthog.com`.

## Maintainer dashboard (PostHog, one-time)

Create an **Adoption** dashboard with four insights:

1. **Invocations over time** — trend of `superhuman_run`.
2. **PRs raised over time** — `superhuman_run` filtered `pr_raised = true`.
3. **Unique adopters** — unique `distinct_id`.
4. **Per-user breakdown** — table of `superhuman_run` by `distinct_id`.
```

- [ ] **Step 2: Add a pointer to `README.md`**

Add this short section near the end of `README.md` (before any license/footer section):

```markdown
## Telemetry

superhuman sends basic, **opt-out** adoption telemetry (your GitHub username,
run count, PR count) to the maintainer's PostHog project. No repo, issue, or
code data is ever sent. Disable with `SUPERHUMAN_TELEMETRY=off` or
`scripts/lib/telemetry_optout.sh`. Full details: [TELEMETRY.md](./TELEMETRY.md).
```

- [ ] **Step 3: Add a pointer to `SECURITY.md`**

Add this short section to `SECURITY.md`:

```markdown
## Telemetry

superhuman collects minimal opt-out usage telemetry. It never transmits
repository contents, diffs, issue data, or local paths — only a GitHub
username and per-run counters. See [TELEMETRY.md](./TELEMETRY.md) for the exact
payload and all opt-out paths.
```

- [ ] **Step 4: Verify the docs reference real, consistent controls**

Run: `grep -l 'SUPERHUMAN_TELEMETRY=off' TELEMETRY.md README.md SECURITY.md && grep -q 'phc_' scripts/lib/usage_ping.sh && echo DOCS_OK`
Expected: prints the three filenames and `DOCS_OK` (confirms the opt-out env var is documented everywhere and the key lives in the emitter).

- [ ] **Step 5: Commit**

```bash
git add TELEMETRY.md README.md SECURITY.md
git commit -m "docs: document opt-out usage telemetry (TELEMETRY.md + pointers)"
```

---

## Self-Review

**1. Spec coverage:**
- PostHog backend, US cloud, embedded key → Task 1 (steps 3, constants). ✓
- One `superhuman_run` event, `pr_raised`/`outcome`/`version` only → Task 1 step 3 payload. ✓
- Invocations + PRs metrics → derived in PostHog, documented Task 4 + Global Constraints. ✓
- Opt-out: `SUPERHUMAN_TELEMETRY=off`, flag file, `telemetry_optout.sh` → Task 1 (steps 1/3), Task 2. ✓
- `print` transparency mode → Task 1 step 3 (step 8 of script) + test case 4. ✓
- First-run notice → Task 1 step 3 (script step 2) + test case 6; visible-when-backgrounded via `/dev/tty`. ✓
- All env vars `SUPERHUMAN_`-prefixed; `DO_NOT_TRACK` dropped → Global Constraints + Task 1. ✓
- Username via `identity.json` cache → `gh` fallback → `unknown` → Task 1 (step 4 of script) + test case 5; cache written by Task 3 Phase 0 edit. ✓
- Fire from `write_run_summary.sh`, non-blocking → Task 3 step 3 (backgrounded). ✓
- Never block/fail the run → `set -uo pipefail`, `exit 0` everywhere, `curl --max-time 3 ... || true`, caller backgrounds + `disown`. ✓
- Docs/disclosure → Task 4. ✓
- Tests in existing plain-bash style → Tasks 1–3. ✓

**2. Placeholder scan:** No TBD/TODO/"handle edge cases"/"similar to". All scripts and tests are complete and inline. ✓

**3. Type/name consistency:** `telemetry.json` schema `{"enabled":bool}` consistent across Task 1 (read), Task 2 (write). `identity.json` schema `{"github_username":string}` consistent across Task 1 (read) and Task 3 (write). `usage_ping.sh --pr-url/--outcome` signature consistent between Task 1 definition and Task 3 caller. Event name `superhuman_run` and property names `pr_raised`/`outcome`/`version` consistent across Task 1 payload, Task 1 tests, and Task 4 docs. ✓
