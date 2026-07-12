#!/usr/bin/env bash
# Unit test for scripts/release/prepare_release.sh. Builds a fixture manifest
# tree in a mktemp dir and points CLAUDE_PLUGIN_ROOT at it — never touches the
# real manifests.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/release/prepare_release.sh"

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

fixture() { # write a fresh fixture tree at version $1
  local v="$1"
  mkdir -p "$tmpdir/.claude-plugin" "$tmpdir/.codex-plugin"
  jq -n --arg v "$v" '{name:"superhuman", version:$v}' > "$tmpdir/.claude-plugin/plugin.json"
  jq -n --arg v "$v" '{name:"superhuman-marketplace", plugins:[{name:"superhuman", version:$v}]}' \
    > "$tmpdir/.claude-plugin/marketplace.json"
  jq -n --arg v "$v" '{name:"superhuman", version:$v}' > "$tmpdir/.codex-plugin/plugin.json"
  cat > "$tmpdir/CHANGELOG.md" <<'EOF'
# Changelog

## [Unreleased]

### Added
- A shiny new thing.

## [0.6.2] — 2026-07-06

### Added
- The previous thing.
EOF
}

run() { CLAUDE_PLUGIN_ROOT="$tmpdir" bash "$SCRIPT" "$@"; }
vof() { jq -r "$2" "$tmpdir/$1"; }

# --- --current: agreeing manifests print the version --------------------------
fixture 0.6.2
got=$(run --current)
[ "$got" = "0.6.2" ] || { echo "FAIL --current: want 0.6.2, got '$got'"; exit 1; }

# --- --current: disagreeing manifests are a config error (exit 10) ------------
jq '.version = "0.6.3"' "$tmpdir/.claude-plugin/plugin.json" > "$tmpdir/p" && mv "$tmpdir/p" "$tmpdir/.claude-plugin/plugin.json"
set +e; run --current >/dev/null 2>&1; rc=$?; set -e
[ "$rc" = "10" ] || { echo "FAIL --current disagreement: want rc 10, got $rc"; exit 1; }

# --- --set: writes all three manifests ---------------------------------------
fixture 0.6.2
new=$(run --set 0.6.3 --date 2026-07-13)
[ "$new" = "0.6.3" ] || { echo "FAIL --set echo: want 0.6.3, got '$new'"; exit 1; }
[ "$(vof .claude-plugin/plugin.json .version)"           = "0.6.3" ] || { echo "FAIL plugin.json not bumped"; exit 1; }
[ "$(vof .claude-plugin/marketplace.json .plugins[0].version)" = "0.6.3" ] || { echo "FAIL marketplace.json not bumped"; exit 1; }
[ "$(vof .codex-plugin/plugin.json .version)"            = "0.6.3" ] || { echo "FAIL codex plugin.json not bumped"; exit 1; }
# after --set the three agree again
[ "$(run --current)" = "0.6.3" ] || { echo "FAIL post-set --current"; exit 1; }

# --- --set: CHANGELOG [Unreleased] is promoted, a fresh [Unreleased] opens ----
grep -qE '^## \[0\.6\.3\] — 2026-07-13' "$tmpdir/CHANGELOG.md" || { echo "FAIL changelog: no dated 0.6.3 section"; exit 1; }
grep -qE '^## \[Unreleased\]'            "$tmpdir/CHANGELOG.md" || { echo "FAIL changelog: no fresh Unreleased"; exit 1; }
# the old Unreleased content now lives under 0.6.3, not under Unreleased
awk '/^## \[Unreleased\]/{u=1;next} /^## \[/{u=0} u && /shiny new thing/{found=1} END{exit found?1:0}' "$tmpdir/CHANGELOG.md" \
  || { echo "FAIL changelog: shiny content should have moved out of Unreleased"; exit 1; }
awk '/^## \[0\.6\.3\]/{s=1;next} /^## \[/{s=0} s && /shiny new thing/{found=1} END{exit found?0:1}' "$tmpdir/CHANGELOG.md" \
  || { echo "FAIL changelog: shiny content should sit under 0.6.3"; exit 1; }

# --- --set: idempotent — re-running does not duplicate the section ------------
run --set 0.6.3 --date 2026-07-13 >/dev/null
[ "$(grep -cE '^## \[0\.6\.3\]' "$tmpdir/CHANGELOG.md")" = "1" ] || { echo "FAIL changelog: 0.6.3 section duplicated"; exit 1; }

# --- --set: rejects non-semver values (anchored, not a loose glob) -----------
# The glob [0-9]*.[0-9]*.[0-9]* accepted these; the workflow splices the value
# into shell/awk, so each is a would-be injection or malformed release.
for bad in "1.2" "1.2.3.4" "1.2.3-rc1" "1.2.3-beta" "1.2.3abc" "v1.2.3" "1.2.3; touch $tmpdir/pwned" "1.2.3
4.5.6"; do
  set +e; run --set "$bad" >/dev/null 2>&1; rc=$?; set -e
  [ "$rc" = "10" ] || { echo "FAIL --set rejects '$bad': want rc 10, got $rc"; exit 1; }
done
[ ! -e "$tmpdir/pwned" ] || { echo "FAIL --set metacharacter value had a side effect"; exit 1; }

# --- --current: agreeing but non-semver manifests are a config error ----------
fixture 0.6.2
for f in .claude-plugin/plugin.json .codex-plugin/plugin.json; do
  jq '.version = "1.2.3-beta"' "$tmpdir/$f" > "$tmpdir/x" && mv "$tmpdir/x" "$tmpdir/$f"
done
jq '.plugins[0].version = "1.2.3-beta"' "$tmpdir/.claude-plugin/marketplace.json" > "$tmpdir/x" \
  && mv "$tmpdir/x" "$tmpdir/.claude-plugin/marketplace.json"
set +e; run --current >/dev/null 2>&1; rc=$?; set -e
[ "$rc" = "10" ] || { echo "FAIL --current non-semver: want rc 10, got $rc"; exit 1; }
fixture 0.6.2

# --- usage errors are exit 10 ------------------------------------------------
for args in "" "--bogus" "--set"; do
  set +e; run $args >/dev/null 2>&1; rc=$?; set -e
  [ "$rc" = "10" ] || { echo "FAIL usage '$args': want rc 10, got $rc"; exit 1; }
done

echo "OK test_prepare_release.sh"
