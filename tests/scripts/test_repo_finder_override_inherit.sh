#!/usr/bin/env bash
# The /repo-finder override path (`--lang`/`--topic`/`--min-stars`) inherits the
# axes it does NOT name from the saved profile. It must read the saved
# `## Filters` block with the SAME detector scripts/lib/preferences.sh uses —
# case-insensitive, spacing-tolerant. A divergent 'exact ## Filters' matcher
# silently fails to inherit on a '## filters' (lowercase, hand-edited) file and
# searches with default axes instead: the silent-wrong-result this whole feature
# exists to prevent. Network-free, bash 3.2-clean.
set -euo pipefail

ROOT="${CLAUDE_PLUGIN_ROOT:-$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)}"
export CLAUDE_PLUGIN_ROOT="$ROOT"
CMD="$ROOT/commands/repo-finder.md"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
HOME="$TMP/home"; export HOME
mkdir -p "$HOME/.superhuman"

fail() { echo "FAIL: $*"; exit 1; }

# A saved profile with a NON-canonical header. /preferences writes '## Filters',
# but preferences.sh accepts '## filters' too, so a hand-edited file can look
# like this — and the override path must read it the same way.
cat > "$HOME/.superhuman/preferences.md" <<'EOF'
## filters
languages: go
topics: backend
stars: 3000
EOF

# The override block is the 2nd ```bash fence. Drive it with a --topic override
# (TOPICS set, LANGS/MIN_STARS empty) so languages + stars MUST be inherited from
# the saved profile. Then print the throwaway file the block compiled.
extract_block2() {
  awk '/^```bash$/{n++; if(n==2){inb=1; next}} /^```$/{inb=0} inb' "$CMD"
}
{
  printf 'LANGS=""\nTOPICS="cli"\nMIN_STARS=""\n'
  extract_block2
  printf 'echo "---OVERRIDE-FILE---"; cat "$OVERRIDE"\n'
} > "$TMP/block.sh"

OUT=$(bash "$TMP/block.sh" 2>&1) || fail "override block errored: $OUT"

case "$OUT" in
  *"languages: go"*) ;;
  *) fail "saved 'languages: go' not inherited from a '## filters' file:
$OUT" ;;
esac
case "$OUT" in
  *"stars: 3000"*) ;;
  *) fail "saved 'stars: 3000' not inherited (fell back to the 2000 default):
$OUT" ;;
esac
case "$OUT" in
  *"topics: cli"*) ;;
  *) fail "--topic override not applied:
$OUT" ;;
esac

echo "OK test_repo_finder_override_inherit.sh"
