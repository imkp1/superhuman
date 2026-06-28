# Changelog

All notable changes to **superhuman** are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/). The `version` field in `.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json` must always match the latest released version here.

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
