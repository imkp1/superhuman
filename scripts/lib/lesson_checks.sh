#!/usr/bin/env bash
# Fixed deterministic-check registry + canonical dedupe key for rule cards.
# Sourced by scripts/lessons/check_lessons.sh (run_check) and, in Plan 2,
# by merge_cards.sh / promote_lessons.sh (is_known_check, card_key).
#
# A deterministic rule card names a check via {"id":..,"args":{..}}. check.id
# MUST be one of the checks below — mined rules may only REFERENCE a check,
# never define one, keeping the executable surface fixed (SAFETY).
#
# run_check returns 0 = pass (satisfied OR not-applicable / fail-open),
# 1 = violated. Checks FAIL OPEN on missing context: a gate never blocks on
# absent data.
#
# Context JSON (assembled by check_lessons.sh):
#   {"worktree":"/abs","changed_files":["a.py"],"head_subject":"fix: x","new_identifiers":["do_thing"]}

known_checks() { echo "file_present file_in_dir commit_matches identifier_case"; }

is_known_check() {
  case " $(known_checks) " in
    *" $1 "*) return 0 ;;
    *) return 1 ;;
  esac
}

# file_present {glob}: a path matching glob exists in the post-diff worktree.
check_file_present() {
  local args="$1" ctx="$2" glob wt rel found=""
  glob=$(printf '%s' "$args" | jq -r '.glob // ""')
  wt=$(printf '%s' "$ctx" | jq -r '.worktree // ""')
  [ -n "$glob" ] || return 0
  [ -n "$wt" ] && [ -d "$wt" ] || return 0
  while IFS= read -r f; do
    rel="${f#$wt/}"
    case "$rel" in
      $glob) found=1; break ;;
    esac
  done < <(find "$wt" -type f 2>/dev/null)
  [ -n "$found" ] && return 0 || return 1
}

# file_in_dir {class, path_glob}: every changed file of `class` lives under path_glob.
# class=test uses basename heuristics; unknown class -> fail-open.
check_file_in_dir() {
  local args="$1" ctx="$2" class pg base is_test violated=""
  class=$(printf '%s' "$args" | jq -r '.class // ""')
  pg=$(printf '%s' "$args" | jq -r '.path_glob // ""')
  [ "$class" = "test" ] || return 0
  [ -n "$pg" ] || return 0
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    base=$(basename "$f")
    is_test=""
    case "$base" in
      test_*|*_test.*|*.test.*|*.spec.*|Test*.*|*Test.*|*Tests.*) is_test=1 ;;
    esac
    [ -n "$is_test" ] || continue
    case "$f" in
      $pg) : ;;
      *)   violated=1 ;;
    esac
  done < <(printf '%s' "$ctx" | jq -r '.changed_files[]? // empty')
  [ -n "$violated" ] && return 1 || return 0
}

# commit_matches {convention}: HEAD subject matches conventional|angular|freeform.
check_commit_matches() {
  local args="$1" ctx="$2" conv subj
  conv=$(printf '%s' "$args" | jq -r '.convention // "freeform"')
  subj=$(printf '%s' "$ctx" | jq -r '.head_subject // ""')
  [ -n "$subj" ] || return 0
  case "$conv" in
    conventional)
      printf '%s' "$subj" | grep -qE '^(feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert)(\([^)]+\))?!?: .+' ;;
    angular)
      printf '%s' "$subj" | grep -qE '^[a-z0-9_.-]+: .+' ;;
    *) return 0 ;;
  esac
}

# identifier_case {style}: every new identifier follows style snake|camel|pascal.
check_identifier_case() {
  local args="$1" ctx="$2" style id violated=""
  style=$(printf '%s' "$args" | jq -r '.style // ""')
  [ -n "$style" ] || return 0
  while IFS= read -r id; do
    [ -n "$id" ] || continue
    case "$style" in
      snake)  printf '%s' "$id" | grep -qE '^[a-z_][a-z0-9_]*$'  || violated=1 ;;
      camel)  printf '%s' "$id" | grep -qE '^[a-z][a-zA-Z0-9]*$'  || violated=1 ;;
      pascal) printf '%s' "$id" | grep -qE '^[A-Z][a-zA-Z0-9]*$'  || violated=1 ;;
      *) return 0 ;;
    esac
    [ -n "$violated" ] && break
  done < <(printf '%s' "$ctx" | jq -r '.new_identifiers[]? // empty')
  [ -n "$violated" ] && return 1 || return 0
}

run_check() {
  local id="$1" args="$2" ctx="$3"
  case "$id" in
    file_present)    check_file_present    "$args" "$ctx" ;;
    file_in_dir)     check_file_in_dir     "$args" "$ctx" ;;
    commit_matches)  check_commit_matches  "$args" "$ctx" ;;
    identifier_case) check_identifier_case "$args" "$ctx" ;;
    *) return 0 ;;
  esac
}

# Canonical dedupe key. Deterministic cards key on their check; semantic cards
# on normalized rule text (lowercased, whitespace-collapsed, trimmed).
card_key() {
  printf '%s' "$1" | jq -r '
    if .kind == "deterministic"
    then "det:" + (.check.id // "") + ":" + ((.check.args // {}) | to_entries | sort_by(.key) | from_entries | tojson)
    else "sem:" + (.rule | ascii_downcase | gsub("\\s+"; " ") | gsub("^\\s+|\\s+$"; ""))
    end'
}
