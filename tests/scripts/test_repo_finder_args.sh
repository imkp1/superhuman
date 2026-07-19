#!/usr/bin/env bash
# Network-free, bash 3.2-clean.
#
# Guards the bug that made `/repo-finder 5` exit 1 with a usage error while every
# unit test stayed green: the command's argv parser was written with $1/$2, but the
# harness expands $1..$9 as slash-command template placeholders BEFORE bash runs.
# `case "$1"` reached the shell as `case ""`, so every token fell through to the
# usage arm. Nothing caught it, because the tests exercised the extracted scripts
# and never the command file as the harness actually delivers it.
#
# So deliver it that way: substitute $ARGUMENTS, blank out $1..$9, run the block,
# and check what it parsed.
set -euo pipefail

ROOT="${CLAUDE_PLUGIN_ROOT:-$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)}"
CMD="$ROOT/commands/repo-finder.md"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

# --- 1. Static: no EXECUTABLE line may read a positional parameter. --------------
# Includes awk field refs ($1, $2, $3): the harness eats those identically, turning
# `printf "%s %s\n",$1,$2` into `printf "%s %s\n",,`. Comments and prose may name
# $1 — that is how the rule documents itself — so scan only live code inside the
# bash fences.
LIVE=$(awk '/^```bash$/{inb=1; next} /^```$/{inb=0} inb' "$CMD" \
       | grep -vE '^[[:space:]]*#')
if printf '%s\n' "$LIVE" | grep -nE '\$\{?[1-9]\}?'; then
  echo "FAIL: commands/repo-finder.md executes a line reading \$1..\$9 (shown above)."
  echo "  The harness substitutes these as template args before bash runs."
  echo "  Use named variables in shell, and shell printf over jq @tsv, not awk."
  exit 1
fi

# --- 2. Behavioural: run the parser the way the harness delivers it. -------------
extract_parser() {
  # First ```bash block in the file is Step 1. Drop the telemetry line: it shells out.
  awk '/^```bash$/{n++; if(n==1){inb=1; next}} /^```$/{inb=0} inb' "$CMD" \
    | grep -v 'usage_event.sh'
}

run_cmd() {  # run_cmd <arguments-string> -> "PARSED:N|LANGS|TOPICS|MIN_STARS", or the error text
  {
    printf 'ARGUMENTS=%s\n' "$(printf '%q' "$1")"
    extract_parser
    printf 'echo "PARSED:$N|$LANGS|$TOPICS|$MIN_STARS"\n'
  } > "$TMP/block.sh"
  # Blank out $1..$9 exactly as the harness does for an unsupplied positional.
  sed -E -i.bak 's/\$\{?[1-9]\}?//g' "$TMP/block.sh"
  bash "$TMP/block.sh" 2>&1 || true
}

expect() {  # expect <label> <args> <substring>
  local out; out=$(run_cmd "$2")
  case "$out" in
    *"$3"*) ;;
    *) echo "FAIL $1: args='$2'"; echo "  expected to contain: $3"; echo "  got: $out"; exit 1 ;;
  esac
}

# The exact invocation that was broken: a bare integer.
expect bare-n          "5"                        "PARSED:5|"
expect default-n       ""                         "PARSED:10|"
expect cap-at-25       "40"                       "PARSED:25|"

# Overrides — the feature this PR ships, which the bug had made unreachable.
expect lang-override   "5 --lang rust"            "PARSED:5|rust||"
expect topic-override  "5 --topic cli"            "PARSED:5||cli|"
expect multi-lang      "--lang go --lang rust"    "PARSED:10|go, rust||"
expect multi-topic     "--topic cli --topic tui"  "PARSED:10||cli, tui|"
expect min-stars       "5 --min-stars 3000"       "PARSED:5|||3000"
expect all-axes        "7 --lang go --topic cli --min-stars 500" "PARSED:7|go|cli|500"

# Loud failures stay loud.
expect no-ceiling      "5 --max-stars 60000"      "There is no star ceiling"
expect bad-flag        "5 --nope"                 "Usage: /repo-finder"
expect dangling-flag   "5 --lang"                 "--lang needs a value"
expect bad-min-stars   "5 --min-stars abc"        "--min-stars must be a positive integer"

echo "OK test_repo_finder_args.sh"
