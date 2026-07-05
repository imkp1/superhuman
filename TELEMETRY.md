# Telemetry

superhuman collects **basic, opt-out** usage telemetry so the maintainer can
measure adoption and prioritize improvements. It is deliberately minimal.

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
