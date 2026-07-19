#!/usr/bin/env bash
# The /repo-finder override path (`--lang`/`--topic`/`--min-stars`) inherits the
# axes it does NOT name from the saved profile. Two contracts:
#
#   1. It reads the saved `## Filters` block with the SAME detector
#      scripts/lib/preferences.sh uses (case-insensitive, spacing-tolerant). A
#      divergent matcher silently fails to inherit on a '## filters' file and
#      searches with defaults instead.
#   2. When it inherits from the saved profile, that profile must be VALID. A
#      malformed saved line (`langauges: go`) is caught on the normal path but
#      would be silently dropped by the key-specific extraction — an override run
#      must not bypass the fail-loud contract.
#
# Network-free, bash 3.2-clean.
set -euo pipefail

ROOT="${CLAUDE_PLUGIN_ROOT:-$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)}"
export CLAUDE_PLUGIN_ROOT="$ROOT"
CMD="$ROOT/commands/repo-finder.md"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
HOME="$TMP/home"; export HOME
mkdir -p "$HOME/.superhuman"

fail() { echo "FAIL: $*"; exit 1; }

# The override block is the 2nd ```bash fence in the command file.
extract_block2() {
  awk '/^```bash$/{n++; if(n==2){inb=1; next}} /^```$/{inb=0} inb' "$CMD"
}

# run_override <saved-content> <LANGS> <TOPICS> <MIN_STARS>
#   Writes the saved profile, drives the override block with the given axes, and
#   prints the block's output (including the compiled $OVERRIDE file on success).
#   Returns the block's exit code.
run_override() {
  printf '%s' "$1" > "$HOME/.superhuman/preferences.md"
  {
    printf 'LANGS=%q\nTOPICS=%q\nMIN_STARS=%q\n' "$2" "$3" "$4"
    extract_block2
    printf 'echo "---OVERRIDE-FILE---"; cat "$OVERRIDE" 2>/dev/null\n'
  } > "$TMP/block.sh"
  bash "$TMP/block.sh" 2>&1
}

# --- Contract 1: inherit unnamed axes from a NON-canonical (lowercase) header. --
SAVED_LC='## filters
languages: go
topics: backend
stars: 3000
'
OUT=$(run_override "$SAVED_LC" "" "cli" "") || fail "override on a valid profile errored: $OUT"
case "$OUT" in *"languages: go"*)   ;; *) fail "saved 'languages: go' not inherited from '## filters':
$OUT" ;; esac
case "$OUT" in *"stars: 3000"*)     ;; *) fail "saved 'stars: 3000' not inherited (fell back to 2000 default):
$OUT" ;; esac
case "$OUT" in *"topics: cli"*)     ;; *) fail "--topic override not applied:
$OUT" ;; esac

# --- Contract 2: a MALFORMED saved profile must fail loud when inherited. -------
# `langauges` (typo) is not `languages:`, so the key-specific extraction drops it
# silently; without validation the override would proceed with a broken profile.
SAVED_BAD='## Filters
langauges: go
topics: backend
'
set +e
OUT=$(run_override "$SAVED_BAD" "" "cli" ""); RC=$?
set -e
[ "$RC" -ne 0 ] || fail "an override that inherits from a MALFORMED saved profile must fail loud, got exit 0:
$OUT"
case "$OUT" in *[Mm]alformed*|*"/preferences"*) ;; *) fail "malformed-saved failure lacked an actionable message:
$OUT" ;; esac

# --- Contract 2, negative: a FULL override never reads the saved profile, so a --
# malformed saved file must NOT block it (nothing is inherited). ---------------
OUT=$(run_override "$SAVED_BAD" "rust" "cli" "500") \
  || fail "a full --lang/--topic/--min-stars override must not be blocked by a malformed saved profile:
$OUT"
case "$OUT" in *"language:rust topic:cli stars:>500"*) ;; *) fail "full override did not compile as given:
$OUT" ;; esac

echo "OK test_repo_finder_override_inherit.sh"
