# Rogue-Proof PR-Body Attribution — Design

**Date:** 2026-07-05
**Status:** Approved for planning
**Author:** brainstormed with maintainer (gaurav0107)

## Problem

`SUPERHUMAN_ATTRIBUTION` (default on) appends a canonical, linked footer to every
PR the plugin opens:

```
🤖 Opened with [Superhuman](https://github.com/gaurav0107/superhuman), an open-source contribution agent.
```

assembled deterministically by `scripts/orchestrator/pr_body_with_attribution.sh`
and piped in at Phase 6 of `agents/opensource-contributor.md`. That footer is
correct and transparent.

The gap: the PR body it wraps (`$PR_BODY_FROM_PLAN`) is **authored by the
model**. When the model writes its *own* attribution line, the filter can't
recognize it — its idempotency check greps only for the literal marker
`Opened with [Superhuman]`, so a differently-worded model line slips through.
Observed on `wwade/jobrunner#428`, which shipped a rogue, unlinked, fine-print
line instead of the canonical footer:

```html
<sub>Prepared with assistance from the Superhuman open-source contribution plugin.</sub>
```

That line is not produced anywhere in the repo — the model improvised it, and
nothing scrubs it. Two failure modes follow:

1. **Rogue attribution.** A model-authored line (unlinked, `<sub>` fine print)
   replaces or coexists with the canonical footer — reads as evasive, the
   opposite of the disclosure's intent.
2. **Double attribution.** Because the model's wording lacks the marker, the
   filter appends the canonical footer *too*, yielding two attributions.

A second, latent gap: Claude/AI attribution is guarded only in **commit
messages** (`agents/builder.md` post-commit check), never in the **PR body**.

## Goal

Make the deterministic footer the **single source of truth** for PR-body
attribution. The harness scrubs any model-authored attribution from the body,
so what remains is exactly the canonical linked footer (attribution on) or
nothing at all (attribution off). Keep the existing footer feature; make it
rogue-proof.

## Non-goals

- No change to the canonical footer text, the `SUPERHUMAN_ATTRIBUTION` flag, or
  its opt-out values (`off`/`false`/`0`/`no`).
- No change to commits — commits remain untouched by this filter (the
  single-author commit rule in `builder.md` is commit-scoped and unchanged).
- Not fixing already-open PRs (e.g. #428); this is forward-looking harness work.

## Decision summary

| Decision | Choice | Why |
|---|---|---|
| Where to enforce | Fold a scrub pass into the existing `pr_body_with_attribution.sh` | Already the single Phase 6 choke point that owns PR-body attribution; already wired and unit-tested. No new files or pipe stages. |
| Mechanism vs prompt | Deterministic scrub **plus** a one-line planner rule | Mirrors `builder.md`'s existing "prompt rule + deterministic guard" pattern. Prompt-only is exactly what failed on #428. |
| Scrub matching | Full-line match (after unwrapping), requiring an attribution **verb + a tool/agent name** | Whole-line + verb+name keeps legitimate prose ("fixes the Claude SDK timeout", "generated the config with make") untouched. |
| Scrub runs when attribution is off? | Yes | "Off" must mean *no* attribution, including rogue lines — otherwise off leaks a model-authored line. The flag only controls whether the canonical footer is re-appended. |

## Architecture

`pr_body_with_attribution.sh` becomes "normalize attribution," not just
"append":

```
plan-authored body ─▶ pr_body_with_attribution.sh
                        │ 1. scrub_attribution(): strip model-authored attribution lines
                        │ 2. collapse orphaned trailing '---' / blank runs left behind
                        │ 3. if SUPERHUMAN_ATTRIBUTION on  → append canonical linked footer
                        │    else                          → emit scrubbed body (no attribution)
                        ▼
                     gh pr create --body
```

Because step 1 removes the canonical footer too, idempotency is preserved by
construction: a second pass strips and re-appends to the same result.

## Scrub specification

`scrub_attribution()` processes the body line by line. A line is **removed**
only when, after unwrapping optional leading/trailing decoration, the **entire
trimmed line** matches an attribution pattern.

**Unwrapping (applied before matching, not mutating kept lines):** strip a
leading blockquote `>`; a leading `🤖`/emoji or `*`/`_` markdown emphasis; and
surrounding `<sub>…</sub>` or `<sup>…</sup>` tags. Matching is case-insensitive.

**A line matches when it is BOTH:**

- an **attribution verb**: `prepared | generated | opened | created | made |
  built | authored | co-authored | written | produced | assisted | with
  assistance`, AND
- a **tool/agent name**: `superhuman | claude | claude code | anthropic | AI
  agent | contribution agent | contribution plugin`.

**Plus these explicit standalone catches** (each already implies verb+name or is
an unambiguous attribution artifact):

- the canonical marker substring `Opened with [Superhuman]`
- a line linking the superhuman repo URL (`github.com/gaurav0107/superhuman`)
- `Co-authored-by:` (line-leading, case-insensitive)
- `noreply@anthropic.com`
- `claude.ai/code` or `claude.com/claude-code`
- `🤖 Generated with`

**Why verb + name (precision over recall):** requiring both means a real
sentence such as "this fixes the Claude SDK timeout" (name present, no
authoring verb aimed at it) or "generated the config with make" (verb present,
`make` is not in the name set) is left intact. This is deliberately a
**whole-line** match — an attribution phrase embedded mid-sentence inside a
paragraph is NOT stripped. That residual is accepted: it is rare and low-harm,
and broader matching would risk corrupting legitimate body content.

**After removal:** if stripping leaves a trailing `---` horizontal rule with
nothing (or only blank lines) after it, drop that orphaned rule; collapse
runs of blank lines created by removal so the body stays clean. Then apply the
existing enable/append logic.

## Components / files

| File | Change |
|---|---|
| `scripts/orchestrator/pr_body_with_attribution.sh` | Add `scrub_attribution()` (awk); run it on `$BODY` before the existing `SUPERHUMAN_ATTRIBUTION` case + append logic. The disable/idempotency/URL-source logic is otherwise unchanged. |
| `tests/scripts/test_pr_body_with_attribution.sh` | Evolve the disable test; add scrub cases (see Testing). |
| `agents/planner.md` | One-line defense-in-depth rule: never author attribution/disclosure lines in the PR body — the harness adds the canonical footer. |

## Testing

Extends the existing plain-bash test (`set -euo pipefail`, string compares,
`OK` on success). Existing passing cases to preserve: default appends footer +
keeps base body + has repo URL; idempotency (marker appears once).

**Evolve:**

- **Disable + clean body** → still returned byte-for-byte (unchanged invariant).
- **Disable + rogue attribution in body** → rogue line removed; output is the
  scrubbed body with **no** footer and **no** rogue line.

**Add:**

1. **Rogue `<sub>` line, attribution on** — body ending in
   `<sub>Prepared with assistance from the Superhuman open-source contribution plugin.</sub>`
   → that line is gone; output carries exactly one canonical
   `Opened with [Superhuman]` footer.
2. **No double attribution** — body where the model already wrote a Superhuman
   attribution line (non-canonical wording) → output has exactly one
   attribution (the canonical footer), marker count 1, rogue wording absent.
3. **Claude/AI attribution in body** — body containing a line
   `🤖 Generated with Claude Code` and a `Co-authored-by: …` line → both stripped
   (default on still yields exactly the canonical footer).
4. **False-positive guard** — body containing the sentences
   `This fixes the Claude SDK timeout.` and
   `We generated the config with make.` → returned intact (neither line
   stripped), footer appended after.
5. **Mid-body `---` preserved** — a body with a real `---` separator between two
   content sections (no attribution after it) → all content preserved; footer
   appended once at the end.

## Defense-in-depth (planner rule)

Add to `agents/planner.md`, alongside its PR-body guidance, a single rule:

> Never write attribution, disclosure, "generated/prepared with", `Co-authored-by`,
> or "Superhuman"/AI-tool credit lines in the PR body. The harness appends the
> canonical disclosure footer itself (`SUPERHUMAN_ATTRIBUTION`). Any such line
> you add will be stripped.

Prompt reduces the occurrence; the scrub makes any occurrence harmless.

## Out of scope (flagged, not built)

The commit-message guard in `builder.md` catches Claude/co-author/anthropic
patterns but not a "Superhuman"-worded attribution in a *commit* message.
Commits should carry no attribution at all, so this is a real but separate,
smaller gap — deliberately excluded here to keep the change focused on the
reported PR-body problem. Track as a follow-up if desired.
