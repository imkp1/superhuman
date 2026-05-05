# opensource-contributor: Improvements from apache/airflow PR #65685

Session date: 2026-04-23 → 2026-04-24
PR: https://github.com/apache/airflow/pull/65685 ("Honor AUTH_ROLE_PUBLIC in FastAPI API server")

This document captures lessons learned from iterating on a real Apache
Airflow contribution through the `opensource-contributor` agent, so we
can harden the agent's workflow.

---

## 1. Executive summary

The agent successfully landed most of the work but repeatedly stumbled
on four axes:

1. **Stale PR metadata** (newsfragment filename, PR description, TODO
   references) survived across review rounds.
2. **Maintainer-requested refactors were applied too literally**, without
   validating that the refactor still worked in *all* callers'
   execution contexts (Flask vs FastAPI startup).
3. **CI signal was interpreted as "push and see"** rather than "verify
   locally first." Each failed CI run cost ~30 min of real wall-clock.
4. **Auto-generated files** (`get_provider_info.py`) were hand-edited
   in one branch and regenerated in CI in another — the agent didn't
   know which tool produced them.

All four are fixable with small, targeted changes to the agent's
playbook and to the mistakes/checks it tracks.

---

## 2. Specific failure modes and recommended fixes

### 2.1 Blindly applying a reviewer's refactor without tracing callers

**What happened**

vincbeck asked to remove the duplicate `conf.get(...)` in
`_get_auth_role_public` and read only from the Flask app config (since
`providers/fab/www/app.py` bridges `[fab] auth_role_public` →
`AUTH_ROLE_PUBLIC`). The agent applied the refactor literally:

```python
if self.appbuilder is not None:
    return self.appbuilder.app.config.get("AUTH_ROLE_PUBLIC", None)
```

This is correct for Flask request paths. But `_get_auth_role_public`
is also called from `get_fastapi_middlewares()`, which runs at FastAPI
startup — **before any Flask application context exists**. The
werkzeug `LocalProxy` behind `appbuilder.app` raised `RuntimeError:
Working outside of application context`, crashing the api-server in
PROD Docker Compose, Kubernetes, e2e, and remote logging tests.

**Root cause in the agent**

The agent read the reviewer's comment as a literal find/replace. It
did not:
- List all callers of the function being refactored
- Classify each caller by execution context (Flask request, Flask
  app ctx, FastAPI startup, CLI, ...)
- Check whether the new implementation is safe in *every* listed
  context

**Recommendation**

Add a "Refactor impact audit" checklist step before accepting any
reviewer-suggested refactor of a function that is called from more
than one layer:

```
Before applying reviewer refactor of `foo.bar`:
  1. `grep -rn "foo.bar\|\.bar("` — list all callers
  2. For each caller, determine execution context:
     - Flask request handler?
     - Flask app-context manager?
     - FastAPI dependency / startup hook / middleware?
     - CLI command?
     - Celery/Airflow task?
  3. For each context × new implementation, answer:
     "Does this work without raising?"
     If unsure, write a 5-line smoke test that exercises it.
  4. If ANY context fails: reply to reviewer with the specific
     context that breaks, propose an alternative (try/except, or
     read the upstream source of truth directly).
```

### 2.2 Not smoke-testing the "auth manager startup" path locally

The actual bug — `Working outside of application context` — would have
surfaced with a four-line local script:

```python
from airflow.providers.fab.auth_manager.fab_auth_manager import FabAuthManager
m = FabAuthManager()
m.get_fastapi_middlewares()   # explodes
```

**Recommendation**

For any edit to an auth manager, middleware registration hook, or
FastAPI lifespan / dependency, the agent should run a *minimal
startup simulator* before pushing:

```python
# .claude/scripts/smoke/fab_startup.py
from airflow.providers.fab.auth_manager.fab_auth_manager import FabAuthManager
m = FabAuthManager()
assert m.get_fastapi_middlewares() is not None
print("FAB auth manager startup: OK")
```

Add to the agent's "pre-push gate" for changes touching:
- `providers/fab/src/airflow/providers/fab/auth_manager/**`
- `airflow-core/src/airflow/api_fastapi/auth/**`
- anything imported by `init_middlewares`

Generalize: the agent should maintain a map of
`(file glob) → (smoke script)` and run the matching smokes before
each push.

### 2.3 Auto-generated files — hand-edit vs regenerate confusion

`providers/fab/src/airflow/providers/fab/get_provider_info.py` is
auto-generated from `provider.yaml` by the
`update-providers-build-files` prek hook. The agent added the yaml
entry but did not regenerate the Python file, so Static checks kept
failing.

When the agent did edit it by hand (this session), it first placed
the entry in the wrong position (after `auth_rate_limited`) because it
didn't check yaml ordering. It had to be moved to the end
(after `cache_ttl`) to match the hook output.

**Recommendation**

1. Maintain a catalog `docs/generated-files.md` inside the agent's
   scratch:

   ```
   providers/*/src/airflow/providers/*/get_provider_info.py
     generator: scripts/ci/prek/update_providers_build_files.py
     source:    providers/*/provider.yaml
     regenerate: breeze static-checks --type update-providers-build-files
   ```

2. Before editing any file in the catalog, the agent should:
   - Prefer running the generator (`breeze static-checks …`)
   - Fall back to hand-editing only if breeze is unavailable; in
     that case, it must read the Jinja template
     (`dev/breeze/src/airflow_breeze/templates/get_provider_info_TEMPLATE.py.jinja2`)
     and reproduce the exact transformation (yaml order, field
     formatting, black formatting).

3. After editing, the agent should cross-check: if CI has a prior
   Static-checks failure log, diff its own output against the exact
   diff the hook produced.

### 2.4 Stale PR metadata survived review rounds

Multiple rounds shipped with:
- Newsfragment filename referencing the wrong issue (`60897` vs
  `65685`)
- PR description still mentioning the old middleware pattern
- Docstrings still naming "FAB" in `base_auth_manager.py` after
  vincbeck asked to keep core provider-agnostic

**Recommendation**

After each `git commit`, the agent should run a "review-drift
linter":

```
Checks:
  - Newsfragments filename = PR number (parse from gh pr view)
  - PR description grep: any mention of functions/classes that no
    longer exist in the diff?
  - Base-layer docstrings: grep for known provider names
    ("fab", "FAB", "kerberos", "ldap", ...) in airflow-core/**
  - Stale "TODO for reviewer X" or "pending" markers
```

Add as a pre-push checklist for `opensource-contributor`.

### 2.5 The merge-probability scorer did not weight "CI-green" heavily

Several rounds scored 70%+ even with 14 failing CI jobs because the
scorer emphasized diff quality + review reply tone, not operational
signal.

**Recommendation**

Update `merge-probability-scorer` to include:

- **CI health gate**: if any required check is failing, cap score
  at 40% until fixed. Display failing job names and last-line error
  signatures prominently.
- **Reviewer sentiment**: approval count, request-changes count,
  staleness of latest request.
- **Mergeable state** via `gh pr view --json mergeable,mergeStateStatus`.

This aligns the score with what a maintainer actually cares about.

### 2.6 Fighting infrastructure flakes vs real bugs

Several failures in round 1 were GitHub HTTP 500s, go1.24.0 fetch
timeouts, and `psycopg2: too many clients already`. The agent spent
time reading these logs.

**Recommendation**

Add a "flake classifier" step before investigating a failure:

```
For each failing job:
  1. Fetch last-20-line log signature
  2. Compare against a maintained flake-signatures file
     (~/.claude/memory/airflow_flakes.md or project-local)
  3. If flake: mark "likely-infrastructure, retry later" and skip
  4. If not: drill in
```

Populate the signatures file over time with known patterns:

```
go1.24.0 fetch timeout → flake
doctoc clone ECONNRESET → flake
psycopg2 "too many clients already" → flake
HTTP 500 from api.github.com during actions/checkout → flake
```

### 2.7 Remote commits auto-pushed by maintainers caused rebase churn

Twice, `git push` was rejected because a maintainer had auto-pushed
a "Merge branch 'main'" commit. The agent had to fetch + rebase.

**Recommendation**

The `opensource-contributor` agent's "push" subroutine should:

```
1. git fetch origin <branch>
2. If remote ahead: git rebase origin/<branch>  (not merge)
3. Re-run pre-push smokes
4. Push with --force-with-lease (not --force)
```

Document this as the standard push flow and bake into the agent's
runbook. Always use `--force-with-lease` for branches that
maintainers may have pushed to.

### 2.8 Fact-forcing gate was triggered repeatedly and felt like overhead

The Fact-Forcing Gate blocked 2 edits in this session, requiring
"who imports this file" + "public API affected" + "data schema"
answers. On both occasions, the facts were already known from
earlier grep output and rewriting them felt like noise.

**Recommendation**

The gate is still valuable (it caught one positioning mistake
yesterday in another session). But the agent should preemptively
produce those facts as the *first step* of any edit, so they're
available when the gate asks. Format them once at the top of the
investigation, reuse the same block if the gate fires later.

### 2.9 Reply tone guidelines need to be persisted

User asked twice for replies to vincbeck to be "softer and more
human." The agent re-tightened on the third round and drifted back
toward formal.

**Recommendation**

Persist per-maintainer tone preferences in the agent's memory:

```
# ~/.claude/projects/.../memory/reply_tone_by_maintainer.md
apache/airflow:
  vincbeck: warm, short, lead with "Good call" / "Thanks for the
            pointer"; avoid "I've addressed your feedback" (too
            corporate)
```

Load it before each reply-drafting step.

---

## 3. Process improvements

### 3.1 Standardize the "ready to push" checklist

The agent should not call `git push` unless every item below is
ticked:

```
[ ] Local pytest passes on the touched test files
[ ] Local ruff + mypy clean on the changed modules
[ ] Startup smokes for affected layers pass (FAB auth, FastAPI
    middleware, Celery task, etc.)
[ ] All auto-generated files are either regenerated by their
    canonical tool OR hand-edited to match the exact output of
    that tool
[ ] Review-drift linter passes (newsfragment, PR description,
    stale TODOs)
[ ] git fetch + rebase complete, working tree clean
[ ] Commit message references the actual root cause, not just
    "fix CI"
```

### 3.2 Keep a `mistakes.md` per active contribution

The superhuman:opensource-contributor skill already mentions a
`mistakes.md` file — this session proves its value. Populate it
with entries like:

```
- 2026-04-23: Refactored _get_auth_role_public per vincbeck's
  request, broke FastAPI startup. Lesson: list callers and
  classify their execution contexts before accepting a refactor.
- 2026-04-23: Hand-edited get_provider_info.py at wrong position;
  regenerator places auth_role_public after cache_ttl, not after
  auth_rate_limited. Lesson: check yaml ordering; prefer running
  the generator.
```

Future rounds on the same PR should re-read this before acting.

### 3.3 Capture "what the reviewer actually meant" notes

Multiple maintainer comments were ambiguous on first read. When the
agent asked "exactly what should I do?", vincbeck clarified in a
follow-up. Capture these interpretations in a file the agent reads
before replying:

```
# reviewer_intent_notes.md
vincbeck on #65685:
  "avoid mentioning a specific provider auth manager in core airflow"
  → keep airflow-core docstrings provider-agnostic; refer to the
    generic mechanism, not FAB by name.
  "no need to check conf.get in other places"
  → duplicate conf reads should be consolidated BUT only if the
    single source is reachable from all call sites.
```

---

## 4. Concrete agent-code changes

Actionable items to fold into the agent:

1. **Pre-push hook**: add a "smokes for touched layers" step keyed
   by file glob.
2. **Generated-file awareness**: maintain a catalog + always prefer
   running the generator tool.
3. **Merge-probability scorer v2**: weight CI health as a hard gate.
4. **Flake classifier**: skip known-infra failures automatically.
5. **Review-drift linter**: newsfragment, PR description, stale
   mentions, layer-specific docstring hygiene.
6. **Per-maintainer tone memory**: persist and load before each reply.
7. **Mistakes log**: enforce write-back after each round.
8. **Standard push flow**: fetch → rebase → smokes → push with
   `--force-with-lease`.

All eight can be implemented as small tool-call additions to the
existing `superhuman:opensource-contributor` skill without changing
its outer loop.

---

## 5. What went well

- The agent correctly diagnosed the `Working outside of application
  context` error from CI logs without needing to reproduce it.
- The fact-forcing gate prevented a wrongly-positioned insert in
  `get_provider_info.py` in an earlier branch.
- The local-first test verification before the final push (125 +
  68 + 204 tests) caught zero regressions and gave confidence.
- The commit message captured the root cause, not just the symptom
  — that will age well in `git blame`.

Keep these behaviors.
