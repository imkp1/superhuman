#!/usr/bin/env bash
# promote_lessons.sh --repo-store FILE [--repo-store FILE ...] --global-store FILE
#                    [--now ISO] [--propose-min 2] [--graduate-min 3]
# Graduated cross-repo promotion (sole caller: lesson-distiller). A repo-scoped
# rule whose card_key recurs across >= propose-min DISTINCT repos becomes a
# global-candidate (advisory); a card reaching >= graduate-min distinct repos
# graduates to global (enforced). Never downgrades an existing global.
# Reuses card_key (single source of truth) to annotate both repo cards and the
# existing global store, then upserts by key. Rewrites the global store (the
# reduce returns the complete merged set).
set -euo pipefail
: "${CLAUDE_PLUGIN_ROOT:?CLAUDE_PLUGIN_ROOT must be set}"
source "${CLAUDE_PLUGIN_ROOT}/scripts/lib/state.sh"
source "${CLAUDE_PLUGIN_ROOT}/scripts/lib/lesson_checks.sh"

GLOBAL=""; NOW=""; PMIN="2"; GMIN="3"; REPO_STORES=()
while [ $# -gt 0 ]; do
  case "$1" in
    --repo-store)   REPO_STORES+=("$2"); shift 2 ;;
    --global-store) GLOBAL="$2"; shift 2 ;;
    --now)          NOW="$2"; shift 2 ;;
    --propose-min)  PMIN="$2"; shift 2 ;;
    --graduate-min) GMIN="$2"; shift 2 ;;
    *) echo "promote_lessons.sh: unknown arg: $1" >&2; exit 2 ;;
  esac
done
[ -n "$GLOBAL" ] || { echo "--global-store required" >&2; exit 2; }
[ -n "$NOW" ] || NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
mkdir -p "$(dirname "$GLOBAL")"
[ -f "$GLOBAL" ] || : > "$GLOBAL"

# Annotate every card in the given store files with its card_key -> {k, c} lines.
annotate() {
  local out="$1"; shift
  local s c k
  : > "$out"
  for s in "$@"; do
    [ -n "$s" ] && [ -f "$s" ] || continue
    while IFS= read -r c || [ -n "$c" ]; do
      [ -n "$c" ] || continue
      k=$(card_key "$c")
      jq -nc --arg k "$k" --argjson c "$c" '{k: $k, c: $c}' >> "$out"
    done < "$s"
  done
}

REPO_ANNOT="${GLOBAL}.repo_annot.$$"
EX_ANNOT="${GLOBAL}.ex_annot.$$"
annotate "$REPO_ANNOT" "${REPO_STORES[@]:-}"
annotate "$EX_ANNOT" "$GLOBAL"

# Group repo cards by key; count DISTINCT repos; keep a representative (highest-confidence) card.
GROUPS_FILE="${GLOBAL}.groups.$$"
jq -s '
  map(select(.c.scope == "repo"))
  | group_by(.k)
  | map({ key:   .[0].k,
          repos: (map(.c.match.repo // "") | unique | map(select(. != ""))),
          rep:   (max_by(.c.confidence).c) })' "$REPO_ANNOT" > "$GROUPS_FILE" 2>/dev/null || echo '[]' > "$GROUPS_FILE"

EXISTING_FILE="${GLOBAL}.existing.$$"
jq -s '.' "$EX_ANNOT" > "$EXISTING_FILE" 2>/dev/null || echo '[]' > "$EXISTING_FILE"

tmpf="${GLOBAL}.tmp.$$"
jq -n \
  --argjson groups "$(cat "$GROUPS_FILE")" \
  --argjson existing "$(cat "$EXISTING_FILE")" \
  --arg now "$NOW" \
  --argjson pmin "$PMIN" \
  --argjson gmin "$GMIN" \
  '($existing | map({(.k): .c}) | add // {}) as $gx
  | reduce ($groups[] | select((.repos | length) >= $pmin)) as $g ($gx;
      (.[$g.key] // ($g.rep
                     | .scope  = "global-candidate"
                     | .id     = ($g.rep.id + "-global")
                     | .source = "outcome"
                     | .created = $now)) as $base
      | .[$g.key] = ( $base
          | .repos_seen    = (((.repos_seen // []) + $g.repos) | unique)
          | .last_confirmed = $now
          | .confidence    = ([ (.confidence // 0), ($g.rep.confidence // 0) ] | max)
          | .scope         = (if .scope == "global" then "global"
                              elif ($g.repos | length) >= $gmin then "global"
                              else "global-candidate" end)
          | .status        = (.status // "active")
          | .hits          = (.hits // 1) ) )
  | [ .[] ]' | jq -c '.[]' > "$tmpf"
mv "$tmpf" "$GLOBAL"
rm -f "$REPO_ANNOT" "$EX_ANNOT" "$GROUPS_FILE" "$EXISTING_FILE"
