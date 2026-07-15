#!/usr/bin/env bash
set -euo pipefail
export CLAUDE_PLUGIN_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

tmpdir=$(mktemp -d)
GD="$tmpdir/.superhuman/global"
mkdir -p "$GD" "$tmpdir/.superhuman/repos/foo-bar"
NOW="2026-05-18T00:00:00Z"

# Eligible: empty blocklist + cooldown
echo '{"version":1,"blocked":[]}' > "$GD/repo_blocklist.json"
echo '{"version":1,"generated_at":"'$NOW'","cooldowns":[]}' > "$GD/repo_cooldown.json"
HOME="$tmpdir" bash "$CLAUDE_PLUGIN_ROOT/scripts/orchestrator/reputation_gate.sh" --repo eligible/repo --now "$NOW" || { echo "FAIL eligible"; exit 1; }

# Blocklisted
echo '{"version":1,"blocked":[{"repo":"bad/repo","reason":"declined","added_at":"'$NOW'","expires_at":null}]}' > "$GD/repo_blocklist.json"
set +e
HOME="$tmpdir" bash "$CLAUDE_PLUGIN_ROOT/scripts/orchestrator/reputation_gate.sh" --repo bad/repo --now "$NOW"
rc=$?
set -e
[ "$rc" = "1" ] || { echo "FAIL blocklist rc: $rc"; exit 1; }

# Cooled down
echo '{"version":1,"blocked":[]}' > "$GD/repo_blocklist.json"
echo '{"version":1,"generated_at":"'$NOW'","cooldowns":[{"repo":"cool/repo","cooldown_until":"2099-01-01T00:00:00Z","negative_outcomes_180d":2,"last_merged_at":null,"triggering_outcomes":[]}]}' > "$GD/repo_cooldown.json"
set +e
HOME="$tmpdir" bash "$CLAUDE_PLUGIN_ROOT/scripts/orchestrator/reputation_gate.sh" --repo cool/repo --now "$NOW"
rc=$?
set -e
[ "$rc" = "2" ] || { echo "FAIL cooldown rc: $rc"; exit 1; }

# Locked
echo '{"version":1,"cooldowns":[]}' > "$GD/repo_cooldown.json"
echo '{"lock_holder":"someone-else"}' > "$tmpdir/.superhuman/repos/foo-bar/current_contribution.json"
set +e
HOME="$tmpdir" bash "$CLAUDE_PLUGIN_ROOT/scripts/orchestrator/reputation_gate.sh" --repo foo/bar --now "$NOW"
rc=$?
set -e
[ "$rc" = "3" ] || { echo "FAIL lock rc: $rc"; exit 1; }

GATE="$CLAUDE_PLUGIN_ROOT/scripts/orchestrator/reputation_gate.sh"

# CLAUDE_PLUGIN_ROOT unset must still produce a VERDICT, by deriving the root from
# the script's own path. It is a template variable: the harness expands it into
# agent and command markdown, so every caller invokes this script by absolute path
# and none of them export it. Demanding it from the environment made the gate exit
# 10 on the first candidate and abort the entire scan for every real caller.
set +e
( unset CLAUDE_PLUGIN_ROOT; HOME="$tmpdir" bash "$GATE" --repo eligible/repo --now "$NOW" ) >/dev/null 2>&1
rc=$?
set -e
[ "$rc" = "0" ] || { echo "FAIL unset CLAUDE_PLUGIN_ROOT rc: $rc (want 0 — must self-derive)"; exit 1; }

# ...but a root that cannot be derived is still a config error, not a verdict. It
# must NOT reuse 1 (blocklisted) or 2 (cooldown): callers drop a repo on any
# nonzero code, so a config error wearing a verdict's exit code silently drops
# every candidate and the scan ends with an empty shortlist that looks like a
# legitimate clean run. Copy the script where its ../.. holds no scripts/lib.
mkdir -p "$tmpdir/orphan/scripts/orchestrator"
cp "$GATE" "$tmpdir/orphan/scripts/orchestrator/reputation_gate.sh"
set +e
( unset CLAUDE_PLUGIN_ROOT
  HOME="$tmpdir" bash "$tmpdir/orphan/scripts/orchestrator/reputation_gate.sh" \
    --repo any/repo --now "$NOW" ) >/dev/null 2>&1
rc=$?
set -e
[ "$rc" = "10" ] || { echo "FAIL underivable root rc: $rc (want 10)"; exit 1; }

# Config error: bad usage. Same rule — must not collide with a verdict code.
set +e
HOME="$tmpdir" bash "$GATE" --bogus-flag x >/dev/null 2>&1
rc=$?
set -e
[ "$rc" = "10" ] || { echo "FAIL unknown arg rc: $rc (want 10)"; exit 1; }

set +e
HOME="$tmpdir" bash "$GATE" --now "$NOW" >/dev/null 2>&1
rc=$?
set -e
[ "$rc" = "10" ] || { echo "FAIL missing --repo rc: $rc (want 10)"; exit 1; }

# Config error: flag given with no value. Under `set -u` the unbound $2 kills
# the script with exit 1 — the "blocklisted" verdict — unless arity is checked
# before $2 is read.
for flag in --repo --now; do
  set +e
  HOME="$tmpdir" bash "$GATE" "$flag" >/dev/null 2>&1
  rc=$?
  set -e
  [ "$rc" = "10" ] || { echo "FAIL $flag with no value rc: $rc (want 10)"; exit 1; }
done

echo "OK test_reputation_gate.sh"
