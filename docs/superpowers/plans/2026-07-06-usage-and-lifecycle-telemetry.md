# Usage & Lifecycle Telemetry Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend superhuman's PostHog telemetry from one event to three — adding a per-command `superhuman_used` event and an install/update `superhuman_lifecycle` event — through the existing single opt-out gate.

**Architecture:** Factor the opt-out/identity/version/send machinery out of `usage_ping.sh` into a sourced `telemetry_common.sh`. A new `usage_event.sh` sources it, emits `superhuman_used`, and infers install/update by diffing `plugin.json`'s version against a cached `last_version.json`. Each command's first bash block backgrounds a call to `usage_event.sh`.

**Tech Stack:** POSIX-ish Bash (3.2-safe), `jq`, `curl`, PostHog capture API.

## Global Constraints

- **Bash 3.2-safe.** No `${var,,}`, no `mapfile`, no bash-4 features.
- **Never block or fail the caller.** Every telemetry script exits 0 on every path. `curl` is bounded `--max-time 3`. Callers background the call (`... >/dev/null 2>&1 & disown 2>/dev/null || true`).
- **Single opt-out gate governs ALL events.** `SUPERHUMAN_TELEMETRY=off`, `~/.superhuman/global/telemetry.json` `{"enabled":false}`, and `SUPERHUMAN_TELEMETRY=print` (dry-run to stderr, no send).
- **Minimal payload.** `distinct_id` = GitHub username. No repo names, issue numbers, diffs, contents, scores, or local paths.
- **PostHog defaults:** key `phc_C8PYp2Sjq6pfQQ8u6f3r37rqdQYnXNVgJEJGQYrDMm8y` (override `SUPERHUMAN_POSTHOG_KEY`), host `https://us.i.posthog.com` (override `SUPERHUMAN_POSTHOG_HOST`), endpoint `/i/v0/e/`.
- **Event names verbatim:** `superhuman_run` (unchanged), `superhuman_used`, `superhuman_lifecycle`.

---

## File Structure

| File | Responsibility |
|---|---|
| `scripts/lib/telemetry_common.sh` | **new** — sourced lib: constants + `th_opted_out`, `th_username`, `th_version`, `th_send` |
| `scripts/lib/usage_ping.sh` | **refactor** — source common lib; identical `superhuman_run` behavior |
| `scripts/lib/usage_event.sh` | **new** — `--command <name>`; emits `superhuman_used` + lifecycle |
| `tests/scripts/test_usage_event.sh` | **new** — opt-out, used-payload, lifecycle install/update/none, unknown-user |
| `commands/*.md` (5 files) | **modify** — one backgrounded `usage_event.sh` call in first bash block |
| `TELEMETRY.md` | **modify** — disclose the two new events |

---

## Task 1: Shared telemetry lib + refactor `usage_ping.sh`

**Files:**
- Create: `scripts/lib/telemetry_common.sh`
- Modify: `scripts/lib/usage_ping.sh` (replace inline gate/identity/version/send with sourced helpers)
- Test: `tests/scripts/test_usage_ping.sh` (existing — must stay green, proves parity)

**Interfaces:**
- Produces (sourced API, all reading env at call time):
  - Constants after source: `POSTHOG_KEY`, `POSTHOG_HOST`, `GLOBAL_DIR`, `FLAG_FILE`, `IDENTITY_FILE`.
  - `th_opted_out` → returns 0 (true = do NOT send; caller should `exit 0`) when env `off` or flag `{"enabled":false}`; else creates the flag file + first-run notice on first ever run and returns 1 (enabled).
  - `th_username` → echoes GitHub username: `identity.json` cache → `gh api user` (cached on success) → `"unknown"`.
  - `th_version` → echoes `plugin.json` `.version` → `"unknown"`.
  - `th_send "<json>"` → print-mode echoes `<json>` to stderr and returns; else bounded silent `curl` POST; never fails.

- [ ] **Step 1: Run the existing test to establish the green baseline**

Run: `bash tests/scripts/test_usage_ping.sh`
Expected: `OK test_usage_ping.sh`

- [ ] **Step 2: Create the shared lib**

Create `scripts/lib/telemetry_common.sh`:

```bash
#!/usr/bin/env bash
# telemetry_common.sh — sourced helpers shared by usage_ping.sh and
# usage_event.sh. Defines constants + functions only; executes nothing at
# source time. Every path is best-effort and must never fail a caller.
# See TELEMETRY.md for the opt-out contract and event catalog.

POSTHOG_KEY="${SUPERHUMAN_POSTHOG_KEY:-phc_C8PYp2Sjq6pfQQ8u6f3r37rqdQYnXNVgJEJGQYrDMm8y}"
POSTHOG_HOST="${SUPERHUMAN_POSTHOG_HOST:-https://us.i.posthog.com}"
GLOBAL_DIR="$HOME/.superhuman/global"
FLAG_FILE="$GLOBAL_DIR/telemetry.json"
IDENTITY_FILE="$GLOBAL_DIR/identity.json"

# th_opted_out: return 0 when telemetry must NOT send, 1 when enabled.
# Side effect: on first ever run, prints the one-time notice and creates
# the flag file (enabled by default — opt-out model).
th_opted_out() {
  [ "${SUPERHUMAN_TELEMETRY:-}" = "off" ] && return 0
  if [ ! -f "$FLAG_FILE" ]; then
    mkdir -p "$GLOBAL_DIR"
    local msg="superhuman records basic usage (a per-run event with your GitHub username and whether a PR was opened) to help the maintainer measure adoption. Disable with SUPERHUMAN_TELEMETRY=off — see TELEMETRY.md."
    { echo "$msg" > /dev/tty; } 2>/dev/null || echo "$msg" >&2
    printf '{"enabled":true}\n' > "$FLAG_FILE"
  fi
  local enabled
  enabled=$(jq -r 'if has("enabled") then .enabled else true end' "$FLAG_FILE" 2>/dev/null || echo true)
  [ "$enabled" = "false" ] && return 0
  return 1
}

# th_username: identity cache -> gh -> "unknown". Caches on gh success.
th_username() {
  local username=""
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
  printf '%s' "$username"
}

# th_version: plugin.json .version -> "unknown".
th_version() {
  jq -r '.version // "unknown"' \
    "${CLAUDE_PLUGIN_ROOT:-}/.claude-plugin/plugin.json" 2>/dev/null || echo "unknown"
}

# th_send <json>: print mode -> stderr (no send); else bounded silent curl.
th_send() {
  local payload="$1"
  if [ "${SUPERHUMAN_TELEMETRY:-}" = "print" ]; then
    echo "$payload" >&2
    return 0
  fi
  curl -sf --max-time 3 -X POST \
    -H 'Content-Type: application/json' \
    -d "$payload" \
    "$POSTHOG_HOST/i/v0/e/" >/dev/null 2>&1 || true
}
```

- [ ] **Step 3: Refactor `usage_ping.sh` to source the lib**

Replace the entire body of `scripts/lib/usage_ping.sh` with:

```bash
#!/usr/bin/env bash
# usage_ping.sh --pr-url <URL|""> --outcome <STRING>
# Best-effort adoption telemetry. Sends one 'superhuman_run' event to PostHog.
# MUST never block or fail the caller: exits 0 on every path, curl is bounded.
set -uo pipefail

# shellcheck source=scripts/lib/telemetry_common.sh
. "$(dirname "$0")/telemetry_common.sh"

PR_URL=""; OUTCOME=""
while [ $# -gt 0 ]; do
  case "$1" in
    --pr-url)  PR_URL="${2:-}"; shift 2 ;;
    --outcome) OUTCOME="${2:-}"; shift 2 ;;
    *) shift ;;   # ignore unknown args; telemetry must never hard-fail
  esac
done

# Opt-out gate (env + persistent flag; creates flag + notice on first run).
th_opted_out && exit 0

username=$(th_username)
version=$(th_version)
if [ -n "$PR_URL" ]; then pr_raised=true; else pr_raised=false; fi

payload=$(jq -nc \
  --arg key "$POSTHOG_KEY" --arg uid "$username" \
  --arg out "$OUTCOME" --arg ver "$version" \
  --argjson pr "$pr_raised" \
  '{api_key:$key, event:"superhuman_run", distinct_id:$uid,
    properties:{pr_raised:$pr, outcome:$out, version:$ver}}' 2>/dev/null) || exit 0

th_send "$payload"
exit 0
```

- [ ] **Step 4: Run the existing test to verify parity**

Run: `bash tests/scripts/test_usage_ping.sh`
Expected: `OK test_usage_ping.sh` (all 7 cases still pass through the shared lib)

- [ ] **Step 5: Commit**

```bash
git add scripts/lib/telemetry_common.sh scripts/lib/usage_ping.sh
git commit -m "refactor: extract telemetry_common.sh; usage_ping sources it (parity)"
```

---

## Task 2: `usage_event.sh` — `superhuman_used` + lifecycle

**Files:**
- Create: `scripts/lib/usage_event.sh`
- Test: `tests/scripts/test_usage_event.sh`

**Interfaces:**
- Consumes: `telemetry_common.sh` (`th_opted_out`, `th_username`, `th_version`, `th_send`, `POSTHOG_KEY`, `GLOBAL_DIR`).
- Produces: CLI `usage_event.sh --command <name>`. Emits `superhuman_used` `{command, version}`; on version change emits `superhuman_lifecycle` `{kind, version, prev_version}`. Reads/writes `$GLOBAL_DIR/last_version.json` = `{"version": "<v>"}`. Always exits 0.

- [ ] **Step 1: Write the failing test**

Create `tests/scripts/test_usage_event.sh`:

```bash
#!/usr/bin/env bash
# tests/scripts/test_usage_event.sh
set -uo pipefail
export CLAUDE_PLUGIN_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT="$CLAUDE_PLUGIN_ROOT/scripts/lib/usage_event.sh"
CURVER=$(jq -r '.version // "unknown"' "$CLAUDE_PLUGIN_ROOT/.claude-plugin/plugin.json")

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

enable() { printf '{"enabled":true}\n' > "$HOME/.superhuman/global/telemetry.json"; }
ident()  { printf '{"github_username":"octocat"}\n' > "$HOME/.superhuman/global/identity.json"; }
lastver(){ printf '{"version":"%s"}\n' "$1" > "$HOME/.superhuman/global/last_version.json"; }

# 1. env opt-out -> no send
setup
SUPERHUMAN_TELEMETRY=off bash "$SCRIPT" --command contribute
[ -s "$CURL_LOG" ] && fail "env off should not send"
teardown

# 2. flag opt-out -> no send
setup
printf '{"enabled":false}\n' > "$HOME/.superhuman/global/telemetry.json"
bash "$SCRIPT" --command contribute
[ -s "$CURL_LOG" ] && fail "flag disabled should not send"
teardown

# 3. used event carries command + version
setup; enable; ident
bash "$SCRIPT" --command repo-finder
grep -q 'superhuman_used'         "$CURL_LOG" || fail "missing used event"
grep -q '"command":"repo-finder"' "$CURL_LOG" || fail "missing command prop"
grep -q "\"version\":\"$CURVER\"" "$CURL_LOG" || fail "missing version prop"
teardown

# 4. lifecycle install: no last_version.json -> kind install, cache written
setup; enable; ident
bash "$SCRIPT" --command contribute
grep -q 'superhuman_lifecycle'   "$CURL_LOG" || fail "install: missing lifecycle event"
grep -q '"kind":"install"'       "$CURL_LOG" || fail "install: wrong kind"
grep -q '"prev_version":""'      "$CURL_LOG" || fail "install: prev_version should be empty"
[ -f "$HOME/.superhuman/global/last_version.json" ] || fail "install: cache not written"
grep -q "\"version\":\"$CURVER\"" "$HOME/.superhuman/global/last_version.json" || fail "install: cache wrong version"
teardown

# 5. lifecycle update: cached older version -> kind update, prev carried
setup; enable; ident; lastver "0.0.1"
bash "$SCRIPT" --command contribute
grep -q '"kind":"update"'         "$CURL_LOG" || fail "update: wrong kind"
grep -q '"prev_version":"0.0.1"'  "$CURL_LOG" || fail "update: missing prev_version"
grep -q "\"version\":\"$CURVER\"" "$HOME/.superhuman/global/last_version.json" || fail "update: cache not bumped"
teardown

# 6. lifecycle none: cached == current -> used sent, NO lifecycle
setup; enable; ident; lastver "$CURVER"
bash "$SCRIPT" --command contribute
grep -q 'superhuman_used'     "$CURL_LOG" || fail "none: used should still send"
grep -q 'superhuman_lifecycle' "$CURL_LOG" && fail "none: lifecycle should NOT send on same version"
teardown

# 7. print mode -> payload on stderr, no send
setup; enable; ident; lastver "$CURVER"
out=$(SUPERHUMAN_TELEMETRY=print bash "$SCRIPT" --command contribute 2>&1 >/dev/null)
echo "$out" | grep -q 'superhuman_used' || fail "print mode should emit used payload"
[ -s "$CURL_LOG" ] && fail "print mode should not send"
teardown

# 8. unknown-user fallback
setup; enable; export GH_FAIL=1
bash "$SCRIPT" --command contribute
grep -q 'unknown' "$CURL_LOG" || fail "should fall back to unknown distinct_id"
teardown

echo "OK test_usage_event.sh"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/scripts/test_usage_event.sh`
Expected: FAIL (the first assertion reached errors because `scripts/lib/usage_event.sh` does not exist yet — `bash: .../usage_event.sh: No such file or directory`, so `CURL_LOG` stays empty or a later grep fails; it must NOT print `OK`).

- [ ] **Step 3: Create `usage_event.sh`**

Create `scripts/lib/usage_event.sh`:

```bash
#!/usr/bin/env bash
# usage_event.sh --command <name>
# Best-effort adoption telemetry. Sends one 'superhuman_used' event, and on
# a version change one 'superhuman_lifecycle' event (install|update).
# MUST never block or fail the caller: exits 0 on every path, curl is bounded.
set -uo pipefail

# shellcheck source=scripts/lib/telemetry_common.sh
. "$(dirname "$0")/telemetry_common.sh"

COMMAND=""
while [ $# -gt 0 ]; do
  case "$1" in
    --command) COMMAND="${2:-}"; shift 2 ;;
    *) shift ;;   # ignore unknown args; telemetry must never hard-fail
  esac
done

# Opt-out gate (env + persistent flag; creates flag + notice on first run).
th_opted_out && exit 0

username=$(th_username)
version=$(th_version)

# 1. superhuman_used — one per command invocation.
used=$(jq -nc \
  --arg key "$POSTHOG_KEY" --arg uid "$username" \
  --arg cmd "$COMMAND" --arg ver "$version" \
  '{api_key:$key, event:"superhuman_used", distinct_id:$uid,
    properties:{command:$cmd, version:$ver}}' 2>/dev/null) || exit 0
th_send "$used"

# 2. superhuman_lifecycle — only on install (no cache) or update (version
#    changed). No native installer hook exists, so we infer from a cached
#    last-seen version.
LAST_VERSION_FILE="$GLOBAL_DIR/last_version.json"
prev=""; kind=""
if [ ! -f "$LAST_VERSION_FILE" ]; then
  kind="install"
else
  prev=$(jq -r '.version // empty' "$LAST_VERSION_FILE" 2>/dev/null || echo "")
  if [ -n "$prev" ] && [ "$prev" != "$version" ]; then
    kind="update"
  fi
fi

if [ -n "$kind" ]; then
  life=$(jq -nc \
    --arg key "$POSTHOG_KEY" --arg uid "$username" \
    --arg kind "$kind" --arg ver "$version" --arg prev "$prev" \
    '{api_key:$key, event:"superhuman_lifecycle", distinct_id:$uid,
      properties:{kind:$kind, version:$ver, prev_version:$prev}}' 2>/dev/null)
  if [ -n "$life" ]; then
    th_send "$life"
    mkdir -p "$GLOBAL_DIR"
    printf '{"version":"%s"}\n' "$version" > "$LAST_VERSION_FILE"
  fi
fi

exit 0
```

- [ ] **Step 4: Make it executable and run the test**

Run: `chmod +x scripts/lib/usage_event.sh && bash tests/scripts/test_usage_event.sh`
Expected: `OK test_usage_event.sh`

- [ ] **Step 5: Confirm `usage_ping` parity is untouched**

Run: `bash tests/scripts/test_usage_ping.sh`
Expected: `OK test_usage_ping.sh`

- [ ] **Step 6: Commit**

```bash
git add scripts/lib/usage_event.sh tests/scripts/test_usage_event.sh
git commit -m "feat: usage_event.sh — superhuman_used + install/update lifecycle telemetry"
```

---

## Task 3: Wire the five commands

**Files:**
- Modify: `commands/contribute.md`, `commands/contribute-loop.md`, `commands/contribution-dashboard.md`, `commands/contribution-fleet.md`, `commands/repo-finder.md`

**Interfaces:**
- Consumes: `scripts/lib/usage_event.sh --command <name>` from Task 2.
- Produces: on each command invocation, a backgrounded best-effort telemetry call that cannot block or fail the command.

- [ ] **Step 1: Add the telemetry line to each command's first bash block**

In each file below, insert these two lines as the **first lines inside the file's first ` ```bash ` code block** (the "Resolve arguments" block), substituting `<name>` per the table. The call is backgrounded and fully swallowed, so its position within the block is immaterial as long as it runs.

Snippet (fill `<name>`):

```bash
# Best-effort adoption telemetry (opt-out). Backgrounded + swallowed so it can
# never block or fail the command. See scripts/lib/usage_event.sh, TELEMETRY.md.
"${CLAUDE_PLUGIN_ROOT}/scripts/lib/usage_event.sh" --command <name> >/dev/null 2>&1 & disown 2>/dev/null || true
```

| File | `<name>` |
|---|---|
| `commands/contribute.md` | `contribute` |
| `commands/contribute-loop.md` | `contribute-loop` |
| `commands/contribution-dashboard.md` | `contribution-dashboard` |
| `commands/contribution-fleet.md` | `contribution-fleet` |
| `commands/repo-finder.md` | `repo-finder` |

- [ ] **Step 2: Verify each file got exactly one instrumented call with the right name**

Run:
```bash
for f in contribute contribute-loop contribution-dashboard contribution-fleet repo-finder; do
  n=$(grep -c "usage_event.sh --command $f" "commands/$f.md")
  [ "$n" -eq 1 ] && echo "OK $f" || echo "BAD $f ($n)"
done
```
Expected: five `OK` lines, no `BAD`.

- [ ] **Step 3: Commit**

```bash
git add commands/contribute.md commands/contribute-loop.md commands/contribution-dashboard.md commands/contribution-fleet.md commands/repo-finder.md
git commit -m "feat: emit superhuman_used telemetry from all five commands"
```

---

## Task 4: Disclose the new events in `TELEMETRY.md`

**Files:**
- Modify: `TELEMETRY.md`

**Interfaces:**
- Consumes: nothing. Documentation must match the payloads emitted in Tasks 1–2.

- [ ] **Step 1: Replace the "What is sent" section**

In `TELEMETRY.md`, replace the section that currently begins `## What is sent` and describes the single `superhuman_run` event (through its property table and the "Nothing else." paragraph) with:

```markdown
## What is sent

Three events, all keyed by `distinct_id` (your GitHub username from
`gh api user`). Nothing else — no repository names, issue numbers, diffs,
file contents, scores, or local paths ever leave your machine. Detailed
metrics stay local in `~/.superhuman/`.

### `superhuman_run` — one per contribution run, at any terminal state

| Field | Example | Meaning |
|---|---|---|
| `pr_raised` | `true` | whether the run opened a pull request |
| `outcome` | `merged_ready` | the run's terminal outcome |
| `version` | `0.6.0` | plugin version |

### `superhuman_used` — one per command invocation

| Field | Example | Meaning |
|---|---|---|
| `command` | `contribute` | which command ran (`contribute`, `contribute-loop`, `contribution-dashboard`, `contribution-fleet`, `repo-finder`) |
| `version` | `0.6.0` | plugin version |

### `superhuman_lifecycle` — once after install or a version change

Emitted on the first command invocation after the plugin is installed or
upgraded (there is no native installer hook, so it is inferred by
comparing the plugin version against a cached last-seen version in
`~/.superhuman/global/last_version.json`).

| Field | Example | Meaning |
|---|---|---|
| `kind` | `update` | `install` (first ever run) or `update` (version changed) |
| `version` | `0.6.0` | current plugin version |
| `prev_version` | `0.5.0` | previous version (empty on install) |

All three events honor the same opt-out below.
```

- [ ] **Step 2: Verify the doc names all three events**

Run: `grep -c 'superhuman_run\|superhuman_used\|superhuman_lifecycle' TELEMETRY.md`
Expected: a count of `3` or more (all three event names now appear).

- [ ] **Step 3: Full telemetry test sweep**

Run: `bash tests/scripts/test_usage_ping.sh && bash tests/scripts/test_usage_event.sh`
Expected:
```
OK test_usage_ping.sh
OK test_usage_event.sh
```

- [ ] **Step 4: Commit**

```bash
git add TELEMETRY.md
git commit -m "docs: disclose superhuman_used and superhuman_lifecycle events"
```

---

## Self-Review Notes

- **Spec coverage:** `telemetry_common.sh` (Task 1) → spec §Components 1; `usage_ping.sh` refactor (Task 1) → §Components 3; `usage_event.sh` + lifecycle inference (Task 2) → §Components 2 + §Event surface rows 2–3; command wiring (Task 3) → §Components 4; `last_version.json` schema (Task 2) → §Data/state files; `TELEMETRY.md` (Task 4) → §Opt-out & transparency; tests (Tasks 1–2) → §Testing. All spec sections mapped.
- **Placeholder scan:** the only `<name>` / `<v>` tokens are explicit substitution templates with a lookup table (Task 3) or literal cache values — no TBD/TODO/"handle edge cases".
- **Type consistency:** `th_opted_out`/`th_username`/`th_version`/`th_send` names, the `POSTHOG_KEY`/`GLOBAL_DIR` constant names, event names (`superhuman_used`, `superhuman_lifecycle`), property names (`command`, `kind`, `version`, `prev_version`), and the `last_version.json` `{"version":...}` schema are identical across the lib definition (Task 1), the emitter (Task 2), the tests (Task 2), and the docs (Task 4).
```