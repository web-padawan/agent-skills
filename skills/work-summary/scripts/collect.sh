#!/usr/bin/env bash
# collect.sh — list the merged pull requests of one author on the default branch of a repo,
# plus the issues that they closed and the issues that the author closed by hand.
#
# Usage:
#   collect.sh [--repo <name|owner/name>] [--since YYYY-MM-DD] [--until YYYY-MM-DD]
#              [--author <login>] [--scope <text>] [--issue-repos <owner/name,...>]
#
# --repo         default vaadin/web-components. A bare name gets the vaadin owner.
# --since        default 30 days ago. --until default today. Both compare the merge date.
# --author       default @me.
# --scope        a component name, for example menu-bar. Case-insensitive.
#                A file matches if its path has a segment named <scope> or vaadin-<scope>,
#                with an optional file extension or a -flow* or -testbench suffix. Under
#                dev/ and test/integration/, a file also matches if a dash-separated part
#                of its name starts with <scope>. Adds the count of matching files.
#                An issue matches by a label <scope> or vaadin-<scope>, or by its title.
# --issue-repos  where to look for issues that the author closed by hand.
#                Default vaadin/web-components,vaadin/flow-components.
#
# Only pull requests merged into the default branch are listed, so backports are left out.
# Closed-by-hand issues come from an `involves:` search, so an issue that the author
# closed with no other involvement (no comment, mention or assignment) is missed.
# With --scope, only pull requests with at least one matching file are listed.
# Output is markdown: a pull request table, closed issues, closed-by-hand issues.
# Read-only: it posts nothing. Requires `jq` and the `gh` CLI, authenticated.
#
# Exit codes: 0 ok · 1 gh could not read the data · 2 usage or environment error.
set -euo pipefail

REPO="vaadin/web-components"
SINCE="$(date -v-30d +%F 2>/dev/null || date -d '30 days ago' +%F)"
UNTIL="$(date +%F)"
AUTHOR="@me"
SCOPE=""
ISSUE_REPOS="vaadin/web-components,vaadin/flow-components"

while [ $# -gt 0 ]; do
  case "$1" in
    --repo) REPO="${2:?--repo requires a value}"; shift ;;
    --since) SINCE="${2:?--since requires a value}"; shift ;;
    --until) UNTIL="${2:?--until requires a value}"; shift ;;
    --author) AUTHOR="${2:?--author requires a value}"; shift ;;
    --scope) SCOPE="${2:?--scope requires a value}"; shift ;;
    --issue-repos) ISSUE_REPOS="${2:?--issue-repos requires a value}"; shift ;;
    --help|-h) sed -n '2,/^# Exit codes/p' "$0"; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
  shift
done
command -v gh >/dev/null || { echo "error: gh CLI not found" >&2; exit 2; }
command -v jq >/dev/null || { echo "error: jq not found" >&2; exit 2; }
[[ "$REPO" == */* ]] || REPO="vaadin/$REPO"
if [ "$AUTHOR" = "@me" ]; then
  AUTHOR="$(gh api user --jq .login)" || exit 1
fi
SCOPE_LC="$(printf '%s' "$SCOPE" | tr '[:upper:]' '[:lower:]')"
SCOPE_RE="$(printf '%s' "$SCOPE_LC" | sed 's/[][\.*^$+?(){}|/]/\\&/g')"
# gh --jq takes no --arg, so the filters read these values through $ENV.
export SCOPE_LC SCOPE_RE AUTHOR

BASE="$(gh repo view "$REPO" --json defaultBranchRef --jq .defaultBranchRef.name)" || exit 1

# One search for all three parts. The limit is raised on purpose, because the default
# of 30 drops pull requests silently. Each PR gets .hits, the count of matching files.
PRS="$(gh pr list --repo "$REPO" --author "$AUTHOR" --state merged --base "$BASE" \
  --search "merged:$SINCE..$UNTIL" --limit 500 \
  --json number,title,mergedAt,files,closingIssuesReferences \
  --jq '
    $ENV.SCOPE_RE as $s |
    ("(^|/)(vaadin-)?" + $s + "(-flow[^/]*|-testbench)?(\\.[^/]*)?(/|$)") as $seg |
    ("^(dev|test/integration)/(.*/)?([^/]*-)?" + $s + "[^/]*$") as $loose |
    map(. + {hits: (if $s == "" then 0 else
      [.files[].path | ascii_downcase | select(test($seg) or test($loose))] | length end)})
  ' 2>/dev/null)" || { echo "error: gh could not list pull requests" >&2; exit 1; }

echo "# Merged pull requests"
echo
echo "repo: $REPO, base: $BASE, author: $AUTHOR, merged: $SINCE..$UNTIL, scope: ${SCOPE:-none}"
echo
echo "| PR | merged | type | title | scope files | closes |"
echo "| --- | --- | --- | --- | --- | --- |"

jq -r '
  ($ENV.SCOPE_RE != "") as $scoped |
  sort_by(.number)[] | select(($scoped | not) or .hits > 0) |
  (.title | capture("^(?<t>[a-z]+)(\\(.*\\))?!?:") // {t: "-"}).t as $type |
  "| #\(.number) | \(.mergedAt[0:10]) | \($type) | \(.title) | \(if $scoped then "\(.hits)/\(.files | length)" else "-" end) | \([.closingIssuesReferences[] | "\(.repository.owner.login)/\(.repository.name)#\(.number)"] | join(" ")) |"
' <<< "$PRS"

if [ -n "$SCOPE" ]; then
  jq -r '"\n\(map(select(.hits == 0)) | length) pull requests with no file that matches the scope are left out."' <<< "$PRS"
fi

# Closing issues of the listed pull requests, by URL, because an issue can live in another repo.
CLOSING="$(jq -r '($ENV.SCOPE_RE != "") as $scoped |
  [.[] | select(($scoped | not) or .hits > 0) | .closingIssuesReferences[].url] | unique | .[]' <<< "$PRS")"

echo
echo "# Issues closed by these pull requests"
echo
for url in $CLOSING; do
  gh issue view "$url" --json number,title,state,labels,url \
    --jq '"- \(.url) \(.state) [\([.labels[].name] | join(", "))] \(.title)"' || true
done

echo
echo "# Issues that $AUTHOR closed by hand, with no pull request"
echo
IFS=',' read -r -a REPOS <<< "$ISSUE_REPOS"
for r in "${REPOS[@]}"; do
  CANDIDATES="$(gh search issues --repo "$r" --closed "$SINCE..$UNTIL" --involves "$AUTHOR" \
    --limit 200 --json number,title,labels \
    --jq '$ENV.SCOPE_LC as $scope | $ENV.SCOPE_RE as $s | .[] |
      select($scope == "" or
        (.title | ascii_downcase | test("(^|[^a-z-])(vaadin-)?" + $s + "($|[^a-z-])")) or
        ([.labels[].name | ascii_downcase | select(. == $scope or . == "vaadin-" + $scope)] | length > 0)) |
      .number' 2>/dev/null)" || continue
  owner="${r%%/*}"; name="${r##*/}"
  for n in $CANDIDATES; do
    # A ClosedEvent with no closer means that a person closed the issue, not a pull request.
    gh api graphql -f query="query { repository(owner:\"$owner\", name:\"$name\") { issue(number:$n) {
        url title stateReason labels(first:20) { nodes { name } }
        timelineItems(itemTypes:[CLOSED_EVENT], last:1) { nodes { ... on ClosedEvent { actor { login } closer { __typename } } } } } } }" \
      --jq '$ENV.AUTHOR as $author | .data.repository.issue |
        (.timelineItems.nodes[0] // {}) as $e |
        select(($e.actor.login // "") == $author and $e.closer == null) |
        "- \(.url) \(.stateReason) [\([.labels.nodes[].name] | join(", "))] \(.title)"' || true
  done
done
