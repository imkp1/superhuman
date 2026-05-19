#!/usr/bin/env bash
# EXTERNAL_CONTENT wrap/unwrap helpers (prompt-injection hardening).
# See agents/SHARED_STATE.md "Prompt-injection hardening" section.

wrap_external() {
  local body="$1"
  local id
  if command -v uuidgen >/dev/null 2>&1; then
    id=$(uuidgen | tr 'A-Z' 'a-z')
  else
    id=$(python3 -c 'import uuid; print(uuid.uuid4())')
  fi
  printf '<<<EXTERNAL_CONTENT id=%s>>>>\n%s\n<<<END id=%s>>>\n' "$id" "$body" "$id"
}

unwrap_external() {
  awk '
    /^<<<EXTERNAL_CONTENT id=/ { in_blk = 1; next }
    /^<<<END id=/              { in_blk = 0; next }
    in_blk == 1                { print }
  '
}
