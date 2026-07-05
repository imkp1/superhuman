# Usage Telemetry (Adoption Analytics) — Design

**Date:** 2026-07-05
**Status:** Approved for planning
**Author:** brainstormed with maintainer (gaurav0107)

## Problem

The maintainer wants to know **how much superhuman is being used** so they can
work toward increasing adoption. Two basic metrics, keyed by the contributor's
GitHub username:

1. **Invocations** — how many times a contribution run is executed.
2. **PRs raised** — how many of those runs actually open a pull request.

Only the maintainer sees the aggregate. All detailed metrics continue to live
locally at the user level (`~/.superhuman/`); nothing detailed leaves the
machine. This is deliberately **basic**, not exhaustive tracking.

## Non-goals

- No per-repo, per-issue, per-diff, or per-score reporting. Those stay local.
- No dashboards or leaderboards visible to end users.
- No blocking, retrying, or failing a contribution run because of telemetry.
- No self-hosted backend, no paid service.

## Decision summary

| Decision | Choice | Why |
|---|---|---|
| Backend | **PostHog** (US cloud, free tier) | Public write-only ingestion key is *designed* to be embedded in open-source clients — no secret to leak. Zero backend code. Dashboards out of the box. Free tier (1M events/mo) dwarfs expected volume. Project key: `phc_C8PYp2Sjq6pfQQ8u6f3r37rqdQYnXNVgJEJGQYrDMm8y`. |
| Consent posture | **Opt-out** (on by default) | Maintainer's explicit choice. Mitigated by a visible first-run notice, a print/dry-run mode, and three off switches. |
| Transport trigger | `write_run_summary.sh` | Already the single source-of-truth terminal hook; runs on **every** terminal state and already knows `--outcome` and `--pr-url`. One hook covers both metrics. |
| Env var namespace | **All `SUPERHUMAN_`-prefixed** | Maintainer's explicit rule. `DO_NOT_TRACK` intentionally **not** honored so every control lives under one namespace (trivially re-addable later if desired). |
| PostHog region | **US cloud** (`https://us.i.posthog.com`) | Maintainer's choice. Overridable via `SUPERHUMAN_POSTHOG_HOST`. |

## Architecture

```
run reaches a terminal state
        │
        ▼
scripts/orchestrator/write_run_summary.sh      (existing single terminal hook)
        │  writes run_summary.json  (unchanged)
        │  then calls ↓  (best-effort, must never block or fail the run)
        ▼
scripts/lib/usage_ping.sh
        │  1. opt-out gate      (SUPERHUMAN_TELEMETRY + telemetry.json flag)
        │  2. resolve username  (identity.json cache → gh api user → "unknown")
        │  3. build payload     (one event: superhuman_run)
        │  4. curl → PostHog    (backgrounded, --max-time 3, output/errors swallowed)
        ▼
PostHog project (US cloud, free tier)
        ▼
Maintainer's saved "Adoption" dashboard
```

No new agents. No new runtime dependency beyond `curl` (already ubiquitous on
macOS/Linux). The client is one small script hung off the existing hook.

**Isolation guarantee:** the contribution flow never waits on telemetry and
never fails because of it. The `curl` is backgrounded (`&`), capped at a 3s
timeout, and all stdout/stderr/exit codes are discarded. Any failure in
`usage_ping.sh` is caught and swallowed by its caller.

## Event schema

Exactly **one** event per terminal run: `superhuman_run`.

```json
{
  "api_key": "phc_C8PYp2Sjq6pfQQ8u6f3r37rqdQYnXNVgJEJGQYrDMm8y",
  "event": "superhuman_run",
  "distinct_id": "<github_username>",
  "properties": {
    "pr_raised": true,
    "outcome": "merged_ready",
    "version": "0.8.0"
  }
}
```

Derived metrics in PostHog:

- **Invocations** = count of `superhuman_run`.
- **PRs raised** = count of `superhuman_run` where `pr_raised = true`.
- **Adopters** = unique `distinct_id`.

`pr_raised` is `true` when `write_run_summary.sh` was called with a non-empty
`--pr-url`, else `false`. `outcome` and `version` ride along for free (both are
already available at the hook) so the maintainer can later see *why* runs don't
convert to PRs. **Nothing else is collected** — no repo names, issue numbers,
diffs, file contents, scores, or local paths.

POST target: `${SUPERHUMAN_POSTHOG_HOST:-https://us.i.posthog.com}/i/v0/e/`
with `Content-Type: application/json`.

### Deduplication (known limitation)

If a run somehow reaches a terminal state twice (crash + retry), two events
could be sent, slightly inflating the invocation count. For v1 this is accepted
as a known limitation — the metric is a coarse adoption signal, not billing.
Optional future hardening: pass a run-scoped id and set PostHog's `$insert_id`
so PostHog dedupes server-side.

## Opt-out mechanism

Enabled by default. Checked in this order; the first match wins:

1. `SUPERHUMAN_TELEMETRY=off` — session/env opt-out.
2. `~/.superhuman/global/telemetry.json` → `{"enabled": false}` — persistent
   opt-out. Set by the documented one-liner or by
   `scripts/lib/telemetry_optout.sh`.
3. Otherwise: enabled.

Additional mode:

- `SUPERHUMAN_TELEMETRY=print` — **transparency / dry-run**. Prints the exact
  JSON payload that *would* be sent to stderr and sends nothing. Lets anyone
  audit precisely what leaves their machine (pattern borrowed from `gh` CLI's
  logging mode).

Env overrides (all `SUPERHUMAN_`-prefixed):

- `SUPERHUMAN_POSTHOG_KEY` — override the embedded ingestion key.
- `SUPERHUMAN_POSTHOG_HOST` — override the host (default `https://us.i.posthog.com`).

### First-run notice

When `~/.superhuman/global/telemetry.json` does not yet exist, `usage_ping.sh`:

1. Prints a one-line notice to **stderr**:
   > `superhuman records anonymous usage counts (your GitHub username, run count, PR count) to help the maintainer measure adoption. Disable with SUPERHUMAN_TELEMETRY=off — see TELEMETRY.md.`
2. Writes `{"enabled": true}` to the flag file (so the notice shows once).
3. Proceeds to send (opt-out semantics).

Non-interactive by design — agents can't prompt, and opt-out doesn't require a
prompt. The notice guarantees the behavior is *disclosed*, which is the
open-source trust requirement.

## Username resolution

`agents/opensource-contributor.md` Phase 0 already derives `GH_USER` from
`gh api user`. Add **one line** there to cache the identity:

```bash
printf '{"github_username":"%s"}\n' "$GH_USER" \
  > "$HOME/.superhuman/global/identity.json"
```

`usage_ping.sh` resolves the username as:

1. Read `github_username` from `~/.superhuman/global/identity.json`.
2. If absent/empty, fall back to `gh api user --jq .login` (and cache it).
3. If that also fails, send `distinct_id: "unknown"` — never error.

## Components / files

| File | Change |
|---|---|
| `scripts/lib/usage_ping.sh` | **new** — opt-out gate, username resolution, payload build, backgrounded curl, first-run notice, print mode |
| `scripts/lib/telemetry_optout.sh` | **new** — writes `{"enabled":false}` to `telemetry.json` (a `--on` counterpart writes `{"enabled":true}`) |
| `scripts/orchestrator/write_run_summary.sh` | after the atomic write, call `usage_ping.sh` with `--pr-url`, `--outcome`; wrap so it can never fail the caller |
| `agents/opensource-contributor.md` | Phase 0: one line caching `GH_USER` to `identity.json` |
| `TELEMETRY.md` | **new** — what is sent, why, exact payload, all opt-out paths, dashboard setup |
| `README.md` / `SECURITY.md` | short pointer to `TELEMETRY.md` |
| `tests/scripts/test_usage_ping.sh` | **new** — opt-out paths, payload shape, print mode, unknown-user fallback |

### `usage_ping.sh` contract

```
usage_ping.sh --pr-url <URL|""> --outcome <STRING>
```

Behavior:

1. Resolve opt-out (env, then flag file); on opt-out, exit 0 silently.
2. Emit first-run notice + create flag file if missing.
3. Resolve `github_username`.
4. Read `version` from `${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json` via `jq`.
5. Compute `pr_raised` = (`--pr-url` non-empty).
6. Build the JSON payload with `jq -nc`.
7. If `SUPERHUMAN_TELEMETRY=print`: print payload to stderr, exit 0.
8. Else: `curl -sf --max-time 3 -X POST -H 'Content-Type: application/json' \
   -d "$payload" "$host/i/v0/e/" >/dev/null 2>&1 &` — backgrounded, disowned,
   all output discarded.

The script sets `set -uo pipefail` (not `-e`) and guards each external call so
a failure anywhere still exits 0. The caller also wraps it defensively:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/lib/usage_ping.sh" \
  --pr-url "$PR" --outcome "$OUT" 2>/dev/null || true
```

## Testing

Plain-bash style matching `tests/scripts/` (`set -euo pipefail`, source/exec,
grep assertions, `echo "OK <name>"`). A stub `curl` is placed first on `PATH`
that records its invocation to a temp file, so no network is touched.

Cases:

1. **Opt-out via env** — `SUPERHUMAN_TELEMETRY=off` ⇒ stub curl **never** called.
2. **Opt-out via flag file** — `telemetry.json` `{"enabled":false}` ⇒ curl never called.
3. **Enabled** ⇒ curl called once; captured payload contains
   `"event":"superhuman_run"`, the right `distinct_id`, and `"pr_raised":true`
   when `--pr-url` is non-empty (and `false` when empty).
4. **Print mode** — `SUPERHUMAN_TELEMETRY=print` ⇒ JSON on stderr, curl never called.
5. **Unknown user** — no `identity.json` and `gh` unavailable ⇒ `distinct_id:"unknown"`, exit 0.
6. **First-run notice** — no `telemetry.json` ⇒ notice printed once, flag file created.

## Dashboard (maintainer, one-time, no code)

Documented in `TELEMETRY.md`. In PostHog (US cloud), create an **Adoption**
dashboard with four saved insights:

1. **Invocations over time** — trend of `superhuman_run`.
2. **PRs raised over time** — `superhuman_run` filtered `pr_raised = true`.
3. **Unique adopters** — unique `distinct_id`.
4. **Per-user breakdown** — table of `superhuman_run` broken down by `distinct_id`.

## Rollout / privacy notes

- `TELEMETRY.md` is the canonical disclosure: exact payload, all opt-out paths,
  and the promise that no repo/issue/diff/path data is ever sent.
- The embedded PostHog key is a **write-only project ingestion key** — safe to
  ship publicly; it cannot read anyone's data.
- Because consent is opt-out, the first-run notice is the trust anchor: usage is
  always *disclosed* before/at the first send.
```