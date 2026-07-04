#!/usr/bin/env bash
# scan_structure.sh --repo OWNER/REPO --worktree DIR [--head-sha SHA] [--now ISO]
# Emits repo_scan.json (structural facts) on stdout — the deterministic scan that
# grounds the lesson-distiller's dossier (producer: repo-profiler). Fields beyond
# {repo,generated_at,head_sha} are best-effort heuristics.
#
# bash-3.2 discipline: uses only find/grep/sed/sort + jq (NO while/case-in-pipe,
# which bash 3.2 mis-parses), and every JSON captured into a shell var is COMPACT
# (jq -c) so `--argjson` is safe. VERIFY UNDER bash, NOT zsh.
set -euo pipefail
: "${CLAUDE_PLUGIN_ROOT:?CLAUDE_PLUGIN_ROOT must be set}"
source "${CLAUDE_PLUGIN_ROOT}/scripts/lib/state.sh"

REPO=""; WT=""; HEAD_SHA=""; NOW=""
while [ $# -gt 0 ]; do
  case "$1" in
    --repo)     REPO="$2"; shift 2 ;;
    --worktree) WT="$2"; shift 2 ;;
    --head-sha) HEAD_SHA="$2"; shift 2 ;;
    --now)      NOW="$2"; shift 2 ;;
    *) echo "scan_structure.sh: unknown arg: $1" >&2; exit 2 ;;
  esac
done
[ -n "$REPO" ] || { echo "--repo required" >&2; exit 2; }
[ -n "$WT" ] && [ -d "$WT" ] || { echo "--worktree DIR (existing) required" >&2; exit 2; }
[ -n "$NOW" ] || NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
[ -n "$HEAD_SHA" ] || HEAD_SHA=$(git -C "$WT" rev-parse HEAD 2>/dev/null || echo "unknown")
DEFAULT_BRANCH=$(git -C "$WT" symbolic-ref --short HEAD 2>/dev/null || echo "main")

KNOWN_EXTS='py js ts go rs java kt cpp cc c rb cs php swift'

# languages: distinct known source extensions present (compact array)
LANGS=$(find "$WT" -type f -not -path '*/.git/*' 2>/dev/null \
  | sed -n 's/.*\.\([a-z][a-z0-9]*\)$/\1/p' | sort -u \
  | jq -R . | jq -sc --argjson known "$(printf '%s\n' $KNOWN_EXTS | jq -R . | jq -sc .)" '[ .[] | select(. as $e | $known | index($e)) ]')

# source_dirs: top-level dir of each source file, minus a test/docs denylist
SRCDIRS=$(find "$WT" -mindepth 2 -type f \( -name '*.py' -o -name '*.js' -o -name '*.ts' -o -name '*.go' -o -name '*.rs' -o -name '*.java' -o -name '*.kt' -o -name '*.rb' \) -not -path '*/.git/*' 2>/dev/null \
  | sed "s#^$WT/##" | sed 's#/.*##' | sort -u | grep -vxE '(tests?|spec|__tests__|docs?|node_modules|vendor|examples)' \
  | jq -R . | jq -sc .)

# test_dirs: any directory whose basename looks like a test dir
TESTDIRS=$(find "$WT" -type d \( -name test -o -name tests -o -name spec -o -name __tests__ \) -not -path '*/.git/*' 2>/dev/null \
  | sed "s#^$WT/##" | sort -u | jq -R . | jq -sc .)

# top_symbols: {file,name} for defs/classes/exports across source files, first 12 (compact)
TOPSYMS=$(grep -rHnE '^(def |class |export default function |export function |function )[A-Za-z_]' "$WT" --include='*.py' --include='*.js' --include='*.ts' --include='*.go' --include='*.rb' 2>/dev/null \
  | grep -v '/\.git/' | sed "s#^$WT/##" | head -12 \
  | jq -Rc '[ inputs | capture("^(?<file>[^:]+):[0-9]+:(def |class |export default function |export function |function )(?<name>[A-Za-z_][A-Za-z0-9_]*)") ]' 2>/dev/null || echo '[]')
[ -n "$TOPSYMS" ] || TOPSYMS='[]'

jq -n --arg repo "$REPO" --arg now "$NOW" --arg head "$HEAD_SHA" --arg db "$DEFAULT_BRANCH" \
  --argjson languages "$LANGS" --argjson source_dirs "$SRCDIRS" \
  --argjson test_dirs "$TESTDIRS" --argjson top_symbols "$TOPSYMS" \
  '{repo:$repo, generated_at:$now, head_sha:$head, default_branch:$db,
    languages:$languages, source_dirs:$source_dirs, test_dirs:$test_dirs,
    test_name_patterns:[], naming:{}, top_symbols:$top_symbols}'
