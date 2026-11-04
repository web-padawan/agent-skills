# pr-history.sh — sourced helpers that read a PR as it was at an earlier time.
#
# An audit of an earlier head must not see what came later: a review comment, a label
# that the review added, or a body that the author rewrote after the review. These
# helpers give the earlier state. Each one prints nothing when gh cannot answer.
# Requires gh and jq.

# pr_slug [<pr-args>...] — owner/name of the PR's base repo, from its URL.
pr_slug() {
  gh pr view "$@" --json url --jq '.url' 2>/dev/null \
    | sed -n 's|^https://[^/]*/\([^/]*/[^/]*\)/pull/.*|\1|p'
}

# valid_iso <text> — succeeds for an ISO 8601 UTC time such as 2026-10-03T08:11:25Z.
valid_iso() {
  [[ "$1" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}(:[0-9]{2})?Z$ ]]
}

# pr_body_as_of <owner/name> <number> <iso-time> — the body as it was at that time.
# GitHub keeps every revision in userContentEdits, with the full text in `diff`. A PR
# with no edit has one revision: the current body.
pr_body_as_of() {
  local slug="$1" number="$2" as_of="$3"
  gh api graphql -f owner="${slug%%/*}" -f name="${slug##*/}" -F number="$number" -f query='
    query($owner:String!,$name:String!,$number:Int!){
      repository(owner:$owner,name:$name){ pullRequest(number:$number){
        body
        userContentEdits(first:100){ nodes{ editedAt diff } } } } }' 2>/dev/null \
    | jq -r --arg asof "$as_of" '.data.repository.pullRequest as $p
      | [$p.userContentEdits.nodes[] | select(.editedAt < $asof)] as $before
      | if ($p.userContentEdits.nodes | length) == 0 then $p.body
        elif ($before | length) > 0 then ($before | sort_by(.editedAt) | last | .diff // "")
        else "" end' 2>/dev/null || true
}
