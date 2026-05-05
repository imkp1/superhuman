# How Superhuman Works

Superhuman is a Claude Code plugin that autonomously contributes to open-source
projects. A thin orchestrator coordinates six specialist agents plus a scorer,
iterating on a pull request until it is merge-ready (or it is clear the run
should stop).

## The Agents

| Agent | Job |
|---|---|
| `repo-finder` | Discovers high-value repos worth contributing to. Produces a ranked shortlist. |
| `issue-selector` | Filters and ranks open issues. Skips docs-only, competing-PR, and <24h-old issues. |
| `repo-profiler` | Reads the last 10–20 merged PRs to learn conventions (commit format, PR body, CI). |
| `planner` | Turns a selected issue into an implementation plan, profile-aware. |
| `builder` | Executes the plan. Runs impact audits before refactors; runs allowlisted CI pre-push. |
| `reviewer-dispatcher` | Picks the weakest scoring dimension and dispatches the matching specialist reviewer. |
| `resolve-comments` | Classifies PR review comments (suspicious / question / nit / refactor / concern) and either replies or dispatches the builder. |
| `merge-probability-scorer` | Scores the open PR across multiple dimensions; records final outcome to the global corpus. |
| `opensource-contributor` | Thin orchestrator. Owns the lock, sequences phases, enforces caps and thresholds. |

## The Pipeline

```
repo-finder → issue-selector → repo-profiler → planner → builder
      ↓                                                     ↓
  shortlist                                            draft PR
                                                          ↓
              ┌── scorer (every iter) ──┬── ≥95% × 2 ──→ merge-ready
              │                         │
              │                         └── <50% after 5 ──→ abandoned
              │
              └── reviewer-dispatcher → builder (apply_findings)
                       ↓
                  resolve-comments → builder (apply_comments)
```

## The Iteration Loop

The orchestrator enforces an **adaptive cap** based on initial diff size:

- < 20 LOC → max 3 iterations
- 20–100 LOC → max 6 iterations
- \> 100 LOC → max 10 iterations

Each iteration:
1. Check if the maintainer already merged/closed the PR.
2. Score the PR with `merge-probability-scorer`.
3. If score ≥ 95% on two consecutive runs → ship as merge-ready.
4. If score < 50% after 5 iterations → abandon.
5. Otherwise: dispatch reviewer-dispatcher → builder → resolve-comments, repeat.

## Shared State

Every run writes to `~/.gstack/projects/superhuman/state/<slug>/`:

- `current_contribution.json` — the run-level lock, protected by `flock(2)`.
- `repo_profile.json`, `ci_commands.json`, `allowed_commands.json` — profiler output.
- `issue_candidates.json` — ranked issue list.
- `scores[]` — appended by the scorer each iteration.
- `mistakes.md` — grows whenever a builder/CI gate fails.

Every terminal outcome (merged, merge_ready, abandoned, plateau,
impact_audit_blocked, suspicious_halt, crash, closed_no_merge) is appended to a
global `merge_outcomes.jsonl` — the calibration corpus that informs future
scoring.

## Safety Rails

- **One run per repo** — real OS-level mutex, not just an advisory field.
- **Fork-only push target** — `origin` is the fork; `upstream` is never written to.
- **AI-policy check** — aborts if `CONTRIBUTING.md` forbids AI-generated code.
- **Rate-limit check** — refuses to start with < 200 GitHub API calls remaining.
- **Impact audit** — before any refactor, the builder lists callers, classifies
  execution contexts, and blocks if the blast radius is unexpected.
- **Suspicious halt** — `resolve-comments` stops the run if it detects a
  prompt-injection attempt in a review comment.
- **Hard thresholds, not vibes** — 95% × 2 to ship, <50% after 5 to abandon.
