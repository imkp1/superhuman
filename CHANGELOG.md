# Changelog

All notable changes to **superhuman** are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/). The `version` field in `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, and `.codex-plugin/plugin.json` must always match the latest released version here.

## [0.8.0] — 2026-07-05

### Added
- **Learning substrate — the system now learns from reviewer feedback instead of repeating it.** A durable, typed knowledge base that outlives a single run and generalizes across repos, closing a Birth → Retrieve → Prevent → Enforce → Curate loop so the same review comments stop recurring across merged PRs.
  - **`lesson-distiller` agent** (producer/curator; sole owner of the knowledge base). *Seed mode* authors a short repo architecture **dossier** grounded in a deterministic structural scan, and emits deterministic scan **rule cards**. *Curate mode* mines a run's classified reviewer comments and merge outcome into typed rule cards, then runs graduated cross-repo promotion, age-based decay, contradiction-demotion, demoted→active re-confirmation, and maintainer-reraise regression logging.
  - **Rule cards** (`schemas/rule_card.schema.json`) — typed, provenance-tracked convention records. Deterministic cards reference one of a fixed check registry (`file_present`, `file_in_dir`, `commit_matches`, `identifier_case`); semantic cards carry prose the scorer's LLM pass judges. A card is DATA — no executable field — and a mined `check.id` outside the registry is force-converted to semantic.
  - **PREVENT** — `planner` and `builder` retrieve the dossier + matching cards (`select_lessons.sh`) and inject them as MUST-follow conventions (planner's Compliance checklist; builder's subagent-driven-development constraints).
  - **ENFORCE** — `merge-probability-scorer` runs `check_lessons.sh` on the diff; an unfixed ENFORCED violation caps the merge score at 75% (blocks merge-ready ≥80%) and lists the rule under Blocking Issues. Shipped violations are logged to a cross-repo regression corpus at terminal only.
  - **Graduated cross-repo promotion** — a repo-scoped rule recurring across ≥2 distinct repos becomes a `global-candidate`; ≥3 graduates it to enforced `global` scope.
  - **Scripts** (all unit-tested, bash-3.2-safe): `scripts/lessons/{select_lessons,check_lessons,merge_cards,promote_lessons,decay_lessons,record_regression,set_lesson_status}.sh`; `scripts/profiler/{scan_structure,write_repo_scan,dossier_fresh}.sh`; `scripts/lib/lesson_checks.sh` (fixed check registry + canonical dedupe key).
  - **Observability** — `/contribution-dashboard` gains a Learning panel: per-repo rule-card counts (total / active / enforced / by kind, plus demoted) and dossier freshness, and a global section with promoted cards (candidate vs. enforced) and the regression alarm log.
- **New shared-state files** (registered in `agents/SHARED_STATE.md`): `repo_scan.json` (owner repo-profiler); `dossier.md`, `dossier_meta.json`, `lessons.jsonl`, `lessons_global.jsonl`, `lesson_regressions.jsonl` (owner lesson-distiller); `classified_comments.json` (owner resolve-comments — the distiller handoff). Each with a draft 2020-12 schema where applicable.

### Changed
- `repo-profiler` now publishes `repo_scan.json` (deterministic structural scan of the worktree) to ground the dossier.
- `resolve-comments` persists classified, non-suspicious comments to `classified_comments.json` for the distiller.
- `opensource-contributor` sequences the distiller: `MODE=seed` after profiling (Phase 2.5) and `MODE=curate` post-terminal (Phase 8.5) — both non-fatal.
- `skills/superhuman/SKILL.md` gained the learning-substrate safety rail for the Codex runtime.

### Security
- Reviewer comments feeding the distiller are treated as EXTERNAL_CONTENT; the distiller extracts ONLY into the constrained rule-card schema. A comment attempting a command, URL, or out-of-repo write is classified `suspicious`, logged to `mistakes.md`, and never minted into a card. Enforced rules feed the scorer's judgment only — they can never expand `allowed_commands.json` or drive builder shell. The active↔demoted transition routes exclusively through `set_lesson_status.sh`; `merge_cards.sh` refuses status-flips-via-merge, so a crafted comment cannot flip an enforced rule by re-merging it.

## [0.7.0] — 2026-06-28

### Added
- **Codex runtime support.** New `.codex-plugin/plugin.json` manifest and `skills/superhuman/SKILL.md` adapter expose the full contribution workflow to Codex. Same `agents/`, `scripts/`, `schemas/` contracts; Codex executes them inline instead of via subagent dispatch.
- **Concrete `superpowers:` fallback procedures** in `skills/superhuman/SKILL.md`. Codex users without the `superpowers` plugin get a 5-section structure for `writing-plans` (Context, Touch list, Implementation steps, Verification, Risks) and a 5-step execution loop for `subagent-driven-development` (read-edit-verify-recover-commit, escalate at 3 failures).
- **Codex command-equivalent table** in README mapping every Claude Code slash command (`/contribute`, `/contribute-loop`, `/contribution-fleet`, `/contribution-dashboard`, `/repo-finder`) to a Codex prompt. Fleet is flagged unsupported since it requires parallel subagent dispatch Codex does not have.
- **Concrete Codex install instructions** — clone + symlink into `~/.codex/skills/superhuman` instead of a hand-wave to "your normal Codex plugin workflow."

### Changed
- Plugin description and keywords updated across `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, and `.codex-plugin/plugin.json` to reflect dual-runtime support.

## [0.5.1] — 2026-06-08

### Fixed
- **Orchestrator could not dispatch.** The Claude Code harness does not grant the `Agent` tool to spawned subagents, so `opensource-contributor` running as a subagent could never fan out to specialists. The orchestrator now executes each specialist contract **inline** — it reads the specialist `.md` and follows it itself — and records `mode: "inline"` in run telemetry. `dispatched` mode is reserved for a future top-level slash-command orchestrator.
- **Manifest drift.** `marketplace.json` had been left at `0.4.1` since v0.5.0 shipped; it is now re-synced with `plugin.json`.

## [0.5.0] — 2026-05-18

### Changed
- **Bash extracted from agent prompts into versioned `scripts/`.** Inline `bash`/`jq` was the bulk of every prompt; moving it out shrinks per-phase load and makes the logic unit-testable. Safety prose (single-author rule, force-with-lease, suspicious-halt) intentionally stays inline in the prompts. Hard constraint for this release: lose no behavior.
- **JSON Schemas formalised under `schemas/`.** Every shared-state file now has a draft 2020-12 schema, validated at write time.

### Added
- Loop primitive commands: `/contribute`, `/repo-finder`, `/contribute-loop`.
- Bash unit-test suite under `tests/scripts/` covering `scripts/` and every schema.

## [0.4.1] — 2026

### Changed
- Declared plugin dependencies (`superpowers` required, `everything-claude-code` recommended) in `plugin.json` under `requires.plugins`.
- Dropped hard-coded `gstack` paths.
- Rewrote the README for public consumption.

## [0.4.0] — 2026

### Added
- `merge-probability-scorer` historical-signal predictor (blends a 10-dimension rubric with past merge outcomes).
- `impact-auditor` agent — refactor blast-radius auditor that blocks reviewer-suggested refactors which break one caller to fix another.
- `/contribution-fleet` parallel run launcher with per-run state isolation and a `flock(2)` mutex.
- Smoke gate in `builder`.

## [0.3.0] — 2026

### Changed
- Hardened the contributor agent — tightened phase sequencing, iteration caps, and merge-threshold handling.

## [0.2.4] — 2026

### Fixed
- Dashboard now runs on macOS's default bash 3.2.

### Added
- Reputation state surfaced in `/contribution-dashboard`.

## [0.2.3] — 2026

### Added
- Reputation gate: repos that consistently reject or ignore PRs land in a cooldown and are skipped by `repo-finder`.

### Changed
- Migrated all persistent state to `~/.superhuman/`.

## [0.2.2] — 2026

### Changed
- Hard-coded the single-author commit rule; forbids `Co-Authored-By:` / AI-attribution trailers. Every commit is authored by the human contributor identity.

## [0.2.0] — 2026

### Changed
- Version bump to trigger plugin cache refresh.

## [0.0.1-beta] — 2026

### Added
- Initial release: orchestrator plus specialist agents for autonomous open-source contribution.

[0.5.1]: https://github.com/gaurav0107/superhuman/releases/tag/v0.5.1
[0.5.0]: https://github.com/gaurav0107/superhuman/releases/tag/v0.5.0
[0.3.0]: https://github.com/gaurav0107/superhuman/releases/tag/v0.3.0
[0.0.1-beta]: https://github.com/gaurav0107/superhuman/releases/tag/v0.0.1-beta
