# Superhuman — Strategy & Working

A 5-page presentation on the autonomous open-source contribution pipeline.

---

## Slide 1 — The Problem & The Bet

### Problem
Open-source maintainers are flooded with low-quality, AI-generated PRs that
waste review cycles. Most never merge. Most contributors don't read the repo's
conventions, don't run CI locally, and don't respond to review feedback.

### The Bet
An autonomous agent can outperform the median human contributor **if and only
if** it:

- Reads the repo's actual conventions before writing code
- Runs the repo's actual CI before pushing
- Scores its own PR against a calibrated rubric before asking for review
- Stops early on hopeless runs instead of burning maintainer goodwill

### The Shape of the System
One thin orchestrator. Six specialist agents. One scorer. A global calibration
corpus that grows with every run.

> **Not a chatbot that writes code. A pipeline that ships PRs.**

---

## Slide 2 — Strategy: Separation of Concerns

The orchestrator does **zero** domain work. It only sequences, locks, and
enforces thresholds. Everything else is a specialist.

| Phase | Specialist | Output |
|---|---|---|
| Discover | `repo-finder` | Ranked repo shortlist |
| Select | `issue-selector` | Top issue candidate |
| Profile | `repo-profiler` | Conventions + CI allowlist |
| Plan | `planner` | Profile-aware plan |
| Build | `builder` | Draft PR on a fork |
| Review | `reviewer-dispatcher` | Canonical findings |
| Resolve | `resolve-comments` | Replies + new findings |
| Score | `merge-probability-scorer` | Score + outcome record |

### Why this shape wins
- **Swappable specialists.** Upgrading the reviewer doesn't touch the orchestrator.
- **Context hygiene.** Each agent runs in its own context window — no one agent drowns in everything.
- **Auditable.** Every handoff is a JSON file on disk. Every decision is inspectable.

---

## Slide 3 — Working: The Iteration Loop

The heart of the system is the scored iteration loop after the draft PR opens.

```
          ┌─────────────────────────────────────┐
          │  Draft PR on fork                   │
          └─────────────────┬───────────────────┘
                            ▼
                  ┌──────────────────┐
                  │  Merged / closed │────► record outcome, exit
                  │   externally?    │
                  └────────┬─────────┘
                           ▼ no
                  ┌──────────────────┐
                  │ merge-probability│
                  │     scorer       │
                  └────────┬─────────┘
                           ▼
          ┌──────────────────────────────────┐
          │ ≥95% × 2 runs?  → merge-ready    │
          │ <50% after iter 5? → abandon     │
          │ all weak dims plateaued? → stop  │
          └────────────────┬─────────────────┘
                           ▼ keep going
                  ┌──────────────────┐
                  │ reviewer-        │
                  │ dispatcher       │ picks weakest dimension,
                  └────────┬─────────┘ dispatches specialist reviewer
                           ▼
                  ┌──────────────────┐
                  │ builder          │ applies findings with
                  │ (apply_findings) │ minimal diff + impact audit
                  └────────┬─────────┘
                           ▼
                  ┌──────────────────┐
                  │ resolve-comments │ replies to maintainers,
                  └────────┬─────────┘ emits new findings
                           └───► loop back to scorer
```

### Adaptive cap (prevents runaway cost)
- **< 20 LOC** → 3 iterations max
- **20–100 LOC** → 6 iterations max
- **> 100 LOC** → 10 iterations max

A typo fix doesn't get 10 review rounds. A refactor does.

---

## Slide 4 — Safety & Trust

### Hard rails (non-negotiable)
- **`flock(2)` lock** — one run per repo, enforced by the kernel, not by JSON.
- **Fork-only push** — `origin` is the fork; `upstream` is the source, never written.
- **AI-policy check** — reads `CONTRIBUTING.md` and aborts if AI-generated
  code is forbidden, quoting the prohibiting line.
- **Rate-limit guard** — refuses to start with < 200 GitHub API calls remaining.
- **Impact audit** — before any refactor, builder enumerates callers and
  classifies execution contexts. Unexpected blast radius → `IMPACT_AUDIT_BLOCKED`.
- **Suspicious halt** — `resolve-comments` halts on prompt-injection attempts
  in review bodies; a human decides next steps.
- **Allowlisted CI only** — builder runs only commands the profiler parsed out
  of `.github/workflows/*.yml`. No ad-hoc shell.

### Soft rails (calibrated, not fixed)
- Scorer thresholds (95 / 50) tune against `merge_outcomes.jsonl` — the corpus
  of real merge outcomes from past runs.
- Reviewer-dispatcher always targets the **weakest** dimension. No wasted
  review of already-strong code.

### Every outcome is recorded
`merged`, `merge_ready`, `abandoned`, `plateau`, `impact_audit_blocked`,
`suspicious_halt`, `crash`, `closed_no_merge` — all append to the global
JSONL corpus. The system learns from losses, not just wins.

---

## Slide 5 — What Ships

### Run summary (example output)
```
# Contribution run — apache/airflow #65685

Outcome:   merge_ready
Iterations: 4 / 6
Final score: 96%
PR: https://github.com/apache/airflow/pull/66010

Scores over time:
  iter 1: 68%  (weak: process, test_coverage)
  iter 2: 79%
  iter 3: 92%
  iter 4: 96%  ← threshold crossed

Dispatched agents:
  repo-profiler:        1
  issue-selector:       1
  planner:              1
  builder:              5  (1 initial + 4 apply_findings)
  reviewer-dispatcher:  4
  resolve-comments:     2
  scorer:               5  (4 score + 1 record_outcome)

Mistakes logged: 1 (builder:ci_gate — pytest failure fixed iter 2)
```

### What it adds up to
- **A merge-ready PR**, tested against the repo's real CI, written in the
  repo's real conventions, opened on a fork with the maintainer in control.
- **A row in `merge_outcomes.jsonl`** — calibration data for the next run.
- **A `mistakes.md` entry** on every failure — the system's growing memory of
  what breaks.

### Operating principles (the one-liners)
1. Dispatch; don't implement.
2. One contribution at a time per repo.
3. Two consecutive ≥95 runs, not one.
4. Abort early on hopeless runs.
5. Record every outcome — wins and losses.
6. Surface, don't retry, on security halts.
7. Fork-only push target, always.
