#!/usr/bin/env bash
# Unquoted word-splitting is a bash-ism. zsh does not split unquoted expansions,
# and zsh is the macOS default shell — so it is the shell that runs the bash
# blocks in agents/ and commands/, and the shell that sources scripts/lib/.
#
#   bash:  NUMS=$'1\n2\n3'; f $NUMS   -> argc=3
#   zsh:   NUMS=$'1\n2\n3'; f $NUMS   -> argc=1
#
# CI runs bash, so CI cannot catch this: every instance fails on the user's machine
# and nowhere else.
#
# Two gates: the code must SURVIVE zsh, and it must not REGROW the pattern.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
fails=0

# --- Gate 1: the sourced libs work under zsh --------------------------------
# scripts/lib/*.sh carry a bash shebang but are SOURCED, so they run in whatever
# shell sources them, and the agent sources them from zsh.
if command -v zsh >/dev/null 2>&1; then
  tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' EXIT
  mkdir -p "$tmp/bin"
  printf '{"required": ["generated_at", "repos"]}\n' > "$tmp/schema.json"
  printf '{"generated_at": "2026-07-13T00:00:00Z", "repos": []}\n' > "$tmp/valid.json"
  printf '{"repos": []}\n' > "$tmp/missing.json"

  # Force the shell-only fallback by hiding python3: that fallback is the stock
  # macOS path (no `python3 -m jsonschema`), and it is the branch that splits.
  printf '#!/bin/sh\nexit 1\n' > "$tmp/bin/python3"
  chmod +x "$tmp/bin/python3"

  # Keep the -c body a constant and pass paths as $1/$2/$3: a checkout or temp path
  # with a quote or shell metacharacter must not break parsing or run unintended
  # commands, and an ordinary path with a quote must not make the test flaky.
  zsh_check='. "$1"
      validate_json "$2" "$3"'
  if ! out=$(PATH="$tmp/bin:$PATH" zsh -c "$zsh_check" zsh-check \
      "$ROOT/scripts/lib/state.sh" "$tmp/schema.json" "$tmp/valid.json" 2>&1); then
    echo "FAIL: validate_json rejects a VALID document under zsh"
    printf '%s\n' "$out" | sed 's/^/    /'
    fails=$((fails + 1))
  fi

  # The fix must not turn the check into a no-op that accepts anything.
  if PATH="$tmp/bin:$PATH" zsh -c "$zsh_check" zsh-check \
      "$ROOT/scripts/lib/state.sh" "$tmp/schema.json" "$tmp/missing.json" >/dev/null 2>&1; then
    echo "FAIL: validate_json accepts a document missing a required field under zsh"
    fails=$((fails + 1))
  fi
else
  echo "SKIP: zsh not installed; the lint below still runs"
fi

# --- Gate 2: the pattern must not grow back ---------------------------------
# Scope is the code that runs under the USER's shell: the bash blocks in agent and
# command markdown, and the libs that get sourced. Scripts under scripts/ with a
# bash shebang are EXECUTED, so their word-splitting is safe and is deliberately
# not linted here.
# Three shapes, all of which need the shell to split for them:
#   for x in $VAR        a list walked as words
#   set -- $VAR          a string reinflated into argv
#   $(f $VAR)            a var spread across a function's arguments
# The trailing filter drops comment lines: the fixes below each explain the very
# pattern they removed, and a lint that flags its own rationale is a lint people
# delete.
# Names may hold digits and uppercase, and the expansion may be braced (${VAR}) —
# match all of those so the unsafe form cannot regrow past the gate.
hits=$(grep -rnE 'for [A-Za-z0-9_]+ in \$\{?[A-Za-z0-9_]+\}?([ 	]*;|[ 	]*$)|set -- \$\{?[A-Za-z0-9_]+\}?|\$\([A-Za-z0-9_]+ \$\{?[A-Za-z0-9_]+\}?\)' \
  "$ROOT/agents" "$ROOT/commands" "$ROOT/scripts/lib" 2>/dev/null \
  | grep -vE '^[^:]+:[0-9]+:[ 	]*#' || true)
if [ -n "$hits" ]; then
  echo "FAIL: unquoted word-splitting in code that runs under zsh:"
  printf '%s\n' "$hits" | sed 's/^/    /'
  echo "    Read the list one item per line instead:"
  echo "      while IFS= read -r x; do [ -n \"\$x\" ] || continue; ...; done <<EOF"
  echo "      \$VAR"
  echo "      EOF"
  fails=$((fails + 1))
fi

[ "$fails" -eq 0 ] || exit 1
echo "OK test_zsh_word_splitting.sh"
