#!/usr/bin/env bash
# Fixtures are paraphrased from the real issues that defeated the pre-filter scan.
set -euo pipefail
CLAUDE_PLUGIN_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
export CLAUDE_PLUGIN_ROOT
FILTER="$CLAUDE_PLUGIN_ROOT/scripts/orchestrator/triage_filter.sh"

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

# Fixed clock: 2026-07-12T00:00:00Z. Fixtures are dated against it so the 24h
# rule is deterministic.
NOW=1783814400
OLD="2026-07-01T00:00:00Z"   # 11 days old — clears the 24h rule
FRESH="2026-07-11T18:00:00Z" # 6 hours old  — must be dropped

printf 'unionlead\n' > "$tmpdir/maintainers.txt"

cat > "$tmpdir/issues.json" <<EOF
[
  {"number": 21795, "title": "Graceful stop on an external file marker",
   "createdAt": "$OLD", "assignees": [], "labels": [{"name": "bug"}],
   "comments": [{"authorAssociation": "COLLABORATOR", "author": {"login": "maint-a"},
     "body": "Thanks, this works today with the public API exactly as you wrote it, and that is by design.",
     "createdAt": "$OLD"}]},

  {"number": 24282, "title": "[BUG] tracing ends up in logs under the gateway",
   "createdAt": "$OLD", "assignees": [], "labels": [{"name": "bug"}],
   "comments": [{"authorAssociation": "MEMBER", "author": {"login": "maint-b"},
     "body": "Thanks for the report. I don't think that this is a bug in this case.",
     "createdAt": "$OLD"}]},

  {"number": 24343, "title": "[BUG] pruner argument is silently ignored",
   "createdAt": "$OLD", "assignees": [{"login": "other-contributor"}], "labels": [{"name": "bug"}],
   "comments": [{"authorAssociation": "MEMBER", "author": {"login": "maint-b"},
     "body": "This bug report makes sense to me, I've assigned you the issue, feel free to submit a fix!",
     "createdAt": "$OLD"}]},

  {"number": 6726, "title": "[BUG]: conv2d_transpose aborts on the GPU",
   "createdAt": "$OLD", "assignees": [], "labels": [{"name": "bug"}],
   "comments": [{"authorAssociation": "MEMBER", "author": {"login": "maint-c"},
     "body": "I see the same thing, and have a kinda hacky patch locally that works around it.",
     "createdAt": "$OLD"}]},

  {"number": 901, "title": "[Discussion] Redesign the connector API",
   "createdAt": "$OLD", "assignees": [], "labels": [{"name": "help wanted"}], "comments": []},

  {"number": 902, "title": "[CI] flaky test", "createdAt": "$OLD", "assignees": [],
   "labels": [{"name": ">test-failure"}],
   "comments": [{"authorAssociation": "MEMBER", "author": {"login": "elasticsearchmachine"},
     "body": "muted; routed to the owning team", "createdAt": "$OLD"}]},

  {"number": 903, "title": "Workspace tree omits deep folders",
   "createdAt": "$OLD", "assignees": [], "labels": [{"name": "bug"}],
   "comments": [{"authorAssociation": "COLLABORATOR", "author": {"login": "maint-d"},
     "body": "Good catch — the tree is scanned server-side with a max depth. PRs welcome!",
     "createdAt": "$OLD"}]},

  {"number": 904, "title": "Union lead blessed this one",
   "createdAt": "$OLD", "assignees": [], "labels": [{"name": "bug"}],
   "comments": [{"authorAssociation": "CONTRIBUTOR", "author": {"login": "unionlead"},
     "body": "Confirmed, happy to review a fix.", "createdAt": "$OLD"}]},

  {"number": 905, "title": "Too fresh to have been triaged", "createdAt": "$FRESH",
   "assignees": [], "labels": [{"name": "good first issue"}], "comments": []},

  {"number": 906, "title": "Untriaged feature request", "createdAt": "$OLD", "assignees": [],
   "labels": [{"name": "needs-triage"}],
   "comments": [{"authorAssociation": "NONE", "author": {"login": "randomuser"},
     "body": "+1, I want this too", "createdAt": "$OLD"}]},

  {"number": 907, "title": "Ghost author must not abort the batch",
   "createdAt": "$OLD", "assignees": [], "labels": [{"name": "bug"}],
   "comments": [{"authorAssociation": "NONE", "author": null,
      "body": "comment from a since-deleted account", "createdAt": "$OLD"},
     {"authorAssociation": "COLLABORATOR", "author": {"login": "maint-d"},
      "body": "Reproduced — PRs welcome.", "createdAt": "$OLD"}]}
]
EOF

OUT="$tmpdir/out.jsonl"
"$FILTER" --issues "$tmpdir/issues.json" --maintainers "$tmpdir/maintainers.txt" --now "$NOW" > "$OUT"

verdict() { jq -r --argjson n "$1" 'select(.number == $n) | .verdict' "$OUT"; }
reason()  { jq -r --argjson n "$1" 'select(.number == $n) | .reason'  "$OUT"; }
field()   { jq -r --argjson n "$1" "select(.number == \$n) | .$2" "$OUT"; }

want() { # want <number> <verdict> <label>
  got=$(verdict "$1")
  [ "$got" = "$2" ] || { echo "FAIL #$1 ($3): want $2, got '${got:-<no verdict>}'"; exit 1; }
}
want_reason() { # want_reason <number> <substring>
  case "$(reason "$1")" in
    *"$2"*) ;;
    *) echo "FAIL #$1 reason: want *$2*, got '$(reason "$1")'"; exit 1 ;;
  esac
}
dropped() { # dropped <number> <label> — failed the gate, so no verdict at all
  [ -z "$(verdict "$1")" ] || { echo "FAIL #$1 ($2): must fail the gate, got '$(verdict "$1")'"; exit 1; }
}

# A maintainer saying "by design" / "I don't think this is a bug" IS engagement.
# The triage gate alone cannot tell that apart from approval.
want 21795 SKIP "maintainer declined (by design)"
want_reason 21795 declined
want 24282 SKIP "maintainer declined (not a bug)"
want_reason 24282 declined

# The strongest possible approval comment, attached to work handed to someone else.
want 24343 SKIP "assigned to another contributor"
want_reason 24343 other-contributor

# The maintainer already holds the patch; ours cannot land.
want 6726 SKIP "maintainer already fixing it"
want_reason 6726 already

# Apache lazy-consensus trap: an RFC wearing a help-wanted label.
want 901 SKIP "discussion/RFC"
want_reason 901 consensus

# A bot is not a maintainer: its comment must not satisfy the triage gate.
dropped 902 "bot-only triage"

# Controls — these must survive.
want 903 KEEP "genuine bug, maintainer invited a PR"
[ "$(field 903 maintainer_comment_assoc)" = "true" ] || { echo "FAIL #903 assoc flag"; exit 1; }

# A union-only lead (comments as CONTRIBUTOR) still passes the gate but earns no
# approval. The distinction PR #25 drew must survive this change.
want 904 KEEP "union-only maintainer"
[ "$(field 904 maintainer_commented)" = "true" ]      || { echo "FAIL #904 union flag"; exit 1; }
[ "$(field 904 maintainer_comment_assoc)" = "false" ] || { echo "FAIL #904 must not claim approval"; exit 1; }

# Pre-existing gates still hold.
dropped 905 "under 24h old"
dropped 906 "needs-triage only, no maintainer"

# A deleted account serializes as author: null, and `null | test(...)` throws —
# one ghost comment aborted the entire batch, taking every other issue with it.
want 907 KEEP "ghost author does not abort the batch"

# Config errors must exit 10, never a verdict code. A config error applies to
# every issue equally, so a verdict-shaped exit empties the candidate set while
# looking like a clean run.
for args in "--issues" "--bogus x" "--maintainers $tmpdir/maintainers.txt"; do
  set +e
  # shellcheck disable=SC2086
  "$FILTER" $args >/dev/null 2>&1
  rc=$?
  set -e
  [ "$rc" = "10" ] || { echo "FAIL config error '$args' rc: $rc (want 10)"; exit 1; }
done

set +e
"$FILTER" --issues "$tmpdir/nope.json" --maintainers "$tmpdir/maintainers.txt" >/dev/null 2>&1
rc=$?
set -e
[ "$rc" = "10" ] || { echo "FAIL missing issues file rc: $rc (want 10)"; exit 1; }

echo "OK test_triage_filter.sh"
