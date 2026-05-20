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

echo "OK test_reputation_gate.sh"
