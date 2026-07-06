# Usage & Lifecycle Telemetry — Design

**Date:** 2026-07-06
**Status:** Approved (pending spec review)
**Builds on:** `docs/superpowers/specs/2026-07-05-usage-telemetry-design.md`

## Problem

Today superhuman sends exactly one PostHog event, `superhuman_run`, fired
from `scripts/orchestrator/write_run_summary.sh` when a contribution run
reaches a terminal state. This measures *outcomes* but not *usage*: we
cannot see which commands people actually invoke, nor when they first
install or upgrade the plugin. We want adoption signal on **any use** and
on **install / update**, without expanding what personal data leaves the
machine and without weakening the existing opt-out.

## Constraints (inherited, non-negotiable)

- **Never block or fail the caller.** Every telemetry path exits 0; the
  `curl` is bounded (`--max-time 3`) and its failure swallowed; callers
  background the invocation.
- **Opt-out is a single gate.** `SUPERHUMAN_TELEMETRY=off` (env), the
  `~/.superhuman/global/telemetry.json` `{"enabled":false}` flag, and
  `SUPERHUMAN_TELEMETRY=print` (dry-run) must govern **all** events, old
  and new, through one code path.
- **Minimal payload.** `distinct_id` is the GitHub username. No repo
  names, issue numbers, diffs, file contents, scores, or local paths ever
  leave the machine.
- **No native install hook exists.** Claude Code plugins get no
  npm-style postinstall callback. Install/update must be *inferred* by
  diffing the current `plugin.json` version against a cached last-seen
  version on the next invocation.

## Event surface (after this change)

| Event | When | Properties |
|---|---|---|
| `superhuman_run` | contribution run hits a terminal state | `pr_raised`, `outcome`, `version` |
| `superhuman_used` | any superhuman command is invoked | `command`, `version` |
| `superhuman_lifecycle` | first invocation after install or version change | `kind` (`install`\|`update`), `version`, `prev_version` |

`distinct_id` = GitHub username on all three. `superhuman_run` is
**unchanged**.

### Why per-command, single event name

One `superhuman_used` event with a `command` property (not one event per
command). This subsumes a coarse "active users" metric — daily actives =
distinct `distinct_id` per day — while also answering *which features get
used*, and it stays a single emitter with a single schema, consistent
with the existing minimal design. All five commands are instrumented,
including `contribution-dashboard` (frequency of dashboard checks is
itself a signal; noise is filterable in PostHog).

### Why lifecycle is its own event

A separate `superhuman_lifecycle` event (rather than a `lifecycle`
property on `superhuman_used`) keeps PostHog funnels clean:
install → first-run → PR. Same-version invocations emit **no** lifecycle
event.

## Architecture

```
commands/*.md  ── (backgrounded call) ──▶  scripts/lib/usage_event.sh
                                                   │ sources
scripts/orchestrator/write_run_summary.sh ─▶ usage_ping.sh
                                                   │ sources
                                        scripts/lib/telemetry_common.sh
                                        (opt-out gate, identity, version,
                                         payload send, print mode)
                                                   │
                                                   ▼
                                          PostHog  /i/v0/e/
```

### Components

1. **`scripts/lib/telemetry_common.sh`** — *new, sourced (not executed).*
   Factors the shared machinery out of today's `usage_ping.sh`:
   - `th_opted_out` → honors `SUPERHUMAN_TELEMETRY=off` and the
     `telemetry.json` `{"enabled":false}` flag, and creates the flag file
     + first-run notice on first ever run (identical semantics to today).
   - `th_username` → `identity.json` cache → `gh api user` → `"unknown"`.
   - `th_version` → `plugin.json` `.version` → `"unknown"`.
   - `th_send <json>` → print-mode branch (`SUPERHUMAN_TELEMETRY=print`
     echoes payload to stderr, sends nothing) else bounded `curl`,
     silent, never fails.
   - Reads `SUPERHUMAN_POSTHOG_KEY` / `SUPERHUMAN_POSTHOG_HOST` overrides
     with the same defaults as today.

2. **`scripts/lib/usage_event.sh`** — *new, executable.*
   Contract: `usage_event.sh --command <name>`.
   - Sources `telemetry_common.sh`; if `th_opted_out` → exit 0.
   - Resolves `username`, `version`.
   - Emits `superhuman_used` `{command, version}` via `th_send`.
   - Lifecycle: reads `~/.superhuman/global/last_version.json`
     (`{"version": "<v>"}`). If absent → `kind=install`, `prev_version`
     empty. If present and `!=` current → `kind=update`,
     `prev_version=<cached>`. Emits `superhuman_lifecycle`
     `{kind, version, prev_version}` only in those two cases, then writes
     the cache to the current version. Same-version → no event, no
     rewrite needed (idempotent).
   - Ignores unknown args (telemetry must never hard-fail). Always
     exits 0.

3. **`scripts/lib/usage_ping.sh`** — *refactor, behavior unchanged.*
   Replace its inline opt-out/identity/version/send blocks with
   `source telemetry_common.sh` + calls to the helpers. The emitted
   `superhuman_run` payload and all opt-out/print semantics are
   byte-for-byte equivalent. Existing `test_usage_ping.sh` must stay
   green.

4. **`commands/*.md`** (all five: `contribute`, `contribute-loop`,
   `contribution-dashboard`, `contribution-fleet`, `repo-finder`) — add
   one line to the top of each command's first bash block:
   ```bash
   # Best-effort adoption telemetry; backgrounded so it never blocks the
   # command. See scripts/lib/usage_event.sh and TELEMETRY.md.
   "${CLAUDE_PLUGIN_ROOT}/scripts/lib/usage_event.sh" --command <name> >/dev/null 2>&1 &
   ```
   `<name>` is the command's own name (`contribute`, `repo-finder`, …).

## Data / state files

| File | Schema | Written by | Read by |
|---|---|---|---|
| `~/.superhuman/global/telemetry.json` | `{"enabled": bool}` | `telemetry_optout.sh`, first-run | common gate |
| `~/.superhuman/global/identity.json` | `{"github_username": str}` | common (on resolve) | common |
| `~/.superhuman/global/last_version.json` | `{"version": str}` | `usage_event.sh` | `usage_event.sh` |

`last_version.json` is **new**. The other two are unchanged.

## Error handling

Every path exits 0. `curl` bounded and swallowed. Missing `jq`, missing
`gh`, missing `CLAUDE_PLUGIN_ROOT`, unreadable cache — all degrade to
`"unknown"`/skip, never a non-zero exit. Backgrounding at the call site
means even a hang cannot stall a command beyond the 3s curl bound in its
own process.

## Opt-out & transparency

The single existing gate governs all three events — no new opt-out knob.
`TELEMETRY.md` is updated to disclose `superhuman_used` and
`superhuman_lifecycle` (fields, meaning, and that they honor the same
opt-out), matching the document's existing "here is exactly what is sent"
contract. `README.md` / `SECURITY.md` telemetry pointers reviewed for
consistency.

## Testing

- **`tests/scripts/test_usage_event.sh`** *(new):*
  - opt-out via env → no send (print-mode assertion emits nothing);
  - opt-out via flag file → no send;
  - `superhuman_used` payload contains the passed `command` and a
    `version`;
  - lifecycle **install**: no `last_version.json` → payload with
    `kind=install`, empty `prev_version`; cache written;
  - lifecycle **update**: cache at older version → `kind=update`,
    `prev_version=<old>`; cache rewritten;
  - lifecycle **none**: cache at current version → no lifecycle payload;
  - unknown-user fallback → `distinct_id="unknown"`.
  Runs entirely in print mode against a temp `HOME`; never hits network.
- **`tests/scripts/test_usage_ping.sh`** *(unchanged)* must still print
  `OK` after the refactor — proves behavior parity.

## Out of scope (YAGNI)

- No per-command opt-out granularity (one gate governs all).
- No SessionStart hook (B2 rejected — loses per-command detail; the
  per-command call sites give precise `command` values).
- No batching/queueing of events; each is an independent bounded curl.
- No new personal data fields.
```