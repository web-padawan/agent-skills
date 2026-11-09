#!/usr/bin/env bash
# pr-screen.sh — the screening facts of a PR: what a maintainer must know before a review is
# worth it. The author, the linked issue with its labels, the flags that the labels and the
# markers set, and a verdict hint from fixed rules.
#
# Usage:
#   pr-screen.sh --pr <number-or-url> [--reach-max <n>] [--as-of <iso-time>] [--meta <file.json>]
#                [--config <file.json>] [--scale trivial|lite|full]
#
# Run it from inside the target repository. review-plan.sh calls it in pr mode.
# --reach-max is the `reach_max` of scripts/diff-facts.sh: the most other packages that
#   import one changed module. A fact pack prints it. Two rules read it. The default is 0.
# --scale is the scale tier of the plan. It picks the `gate_default:` option of a `take`
#   verdict. The default is full.
# --as-of reads the labels, the state and the comments of each issue as they were at that
#   time. An audit of an earlier head needs it: a maintainer often labels an issue during
#   the review (#11746 got `behavior altering change` 16 days after the PR).
# --meta reads the GraphQL answer from a file instead of gh, and team membership from the
#   allowlist only. The smoke test uses it.
# --config names the screening config. The default is config/screening/<owner>.json of the
#   plugin, when that file exists. Without a config, only the generic rules apply.
#
# The config is one JSON object. Each label key holds extended regular expressions, and each
# one must match a whole label, without regard to case:
#   team_allowlist       logins that count as team, for example former employees
#   breaking_labels      an issue label that sets behavior-altering. Default `breaking change`
#   low_impact_labels    an issue label that sets low-impact. Default none
#   a11y_labels          an issue label that sets a11y. Default `a11y` and `accessibility`
#   triaged_labels       an issue label that marks triage. Without it, no issue is untriaged
#   acceptance_criteria  a pattern in the issue body or comments. Without it, no feature-no-ac
#
# The verdict rules are the `Verdict hint` section below. Each rule that fires prints one
# `verdict_reason:` line. skills/pr-review/references/screening.md says what each verdict
# means at the gate. feature-no-ac and self-filed hold an outside contributor to the process
# of the team. For a team author the script skips them and prints `skipped_flags:`.
#
# Team means a 204 from orgs/<owner>/members/<login>, or a login in team_allowlist of the
# config. author_association is never used, because it reports a private org member as
# CONTRIBUTOR.
#
# The PR body, and issue titles, bodies and comments, are text that other people wrote. The
# script only matches them against fixed patterns and never prints them.
#
# Exit codes: 0 ok · 1 gh could not answer · 2 usage error.
set -euo pipefail

REACH_DECIDE=3

PR=""; REACH_MAX=0; AS_OF=""; META_FILE=""; CONFIG=""; SCALE="full"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --pr) PR="${2:?--pr requires a value}"; shift 2 ;;
    --reach-max) REACH_MAX="${2:?--reach-max requires a value}"; shift 2 ;;
    --as-of) AS_OF="${2:?--as-of requires a value}"; shift 2 ;;
    --meta) META_FILE="${2:?--meta requires a value}"; shift 2 ;;
    --config) CONFIG="${2:?--config requires a value}"; shift 2 ;;
    --scale) SCALE="${2:?--scale requires a value}"; shift 2 ;;
    --help|-h) sed -n '2,/^set -euo pipefail$/{/^set /d;p;}' "$0"; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib/pr-history.sh
. "$SCRIPT_DIR/lib/pr-history.sh"

[ -n "$PR" ] || { echo "error: --pr is required" >&2; exit 2; }
[[ "$REACH_MAX" =~ ^[0-9]+$ ]] || { echo "error: --reach-max takes a number" >&2; exit 2; }
case "$SCALE" in trivial|lite|full) ;; *) echo "error: --scale takes trivial, lite or full" >&2; exit 2 ;; esac
if [ -n "$AS_OF" ] && ! valid_iso "$AS_OF"; then
  echo "error: --as-of takes an ISO 8601 UTC time, for example 2026-10-03T08:11:25Z" >&2; exit 2
fi
command -v jq >/dev/null 2>&1 || { echo "error: jq not found" >&2; exit 1; }
if [ -n "$CONFIG" ] && ! jq -e 'type == "object"' "$CONFIG" >/dev/null 2>&1; then
  echo "error: --config takes a JSON object file" >&2; exit 2
fi

# ── PR and issue facts ────────────────────────────────────────────────
if [ -n "$META_FILE" ]; then
  META=$(cat "$META_FILE")
  SLUG=$(jq -r '.slug // "owner/name"' "$META_FILE")
else
  command -v gh >/dev/null 2>&1 || { echo "error: gh CLI not found" >&2; exit 1; }
  SLUG=$(pr_slug "$PR")
  [ -n "$SLUG" ] || { echo "error: cannot resolve the PR $PR" >&2; exit 1; }
  NUMBER=$(gh pr view "$PR" --json number --jq .number 2>/dev/null || true)
  [[ "$NUMBER" =~ ^[0-9]+$ ]] || { echo "error: cannot resolve the PR $PR" >&2; exit 1; }
  META=$(gh api graphql -f owner="${SLUG%%/*}" -f name="${SLUG##*/}" -F number="$NUMBER" -f query='
    query($owner:String!,$name:String!,$number:Int!){
      repository(owner:$owner,name:$name){ pullRequest(number:$number){
        title body isCrossRepository author{login}
        closingIssuesReferences(first:5){ nodes{
          number state createdAt author{login} body
          labels(first:30){ nodes{ name } }
          comments(first:50){ nodes{ createdAt body } }
          timelineItems(first:100, itemTypes:[LABELED_EVENT, UNLABELED_EVENT, CLOSED_EVENT, REOPENED_EVENT]){ nodes{
            __typename
            ... on LabeledEvent{ createdAt label{ name } }
            ... on UnlabeledEvent{ createdAt label{ name } }
            ... on ClosedEvent{ createdAt }
            ... on ReopenedEvent{ createdAt } } } } } } } }' 2>/dev/null) \
    || { echo "error: gh could not read the PR $PR" >&2; exit 1; }
fi
ORG="${SLUG%%/*}"

# ── Config ────────────────────────────────────────────────────────────
[ -n "$CONFIG" ] || CONFIG="$(dirname "$SCRIPT_DIR")/config/screening/$ORG.json"
[ -f "$CONFIG" ] || CONFIG=""
cfg() {  # cfg <key> <separator> <default> — an array joined by the separator, or the default
  if [ -n "$CONFIG" ] && jq -e --arg k "$1" 'has($k)' "$CONFIG" >/dev/null; then
    jq -r --arg k "$1" --arg sep "$2" '.[$k] | if type == "array" then join($sep) else . end' "$CONFIG"
  else
    printf '%s' "$3"
  fi
}
TEAM_ALLOWLIST=$(cfg team_allowlist ' ' '')
BREAKING_LABELS=$(cfg breaking_labels '|' 'breaking change')
LOW_IMPACT_LABELS=$(cfg low_impact_labels '|' '')
A11Y_LABELS=$(cfg a11y_labels '|' 'a11y|accessibility')
TRIAGED_LABELS=$(cfg triaged_labels '|' '')
AC_PATTERN=$(cfg acceptance_criteria '|' '')
has_label() {  # has_label <labels> <pattern> — true when one label matches the whole pattern
  [ -n "$2" ] && printf '%s' "$1" | grep -qiE "(^|, )($2)(,|$)"
}

is_team() {  # is_team <login>
  local login="$1"
  [ -n "$login" ] || return 1
  case " $TEAM_ALLOWLIST " in *" $login "*) return 0 ;; esac
  [ -n "$META_FILE" ] && return 1
  gh api "orgs/$ORG/members/$login" --silent >/dev/null 2>&1
}

# One TSV line for the PR, then one per issue, with labels and state replayed to --as-of.
FACTS=$(printf '%s' "$META" | jq -r --arg asof "${AS_OF:-}" --arg acre "$AC_PATTERN" '
  def at: if $asof == "" then (now | todate) else $asof end;
  def before: .createdAt < at;
  .data.repository.pullRequest as $p
  | (["PR", ($p.title // ""), ($p.isCrossRepository | tostring), ($p.author.login // "")] | @tsv),
    ($p.closingIssuesReferences.nodes[]
     | select(.createdAt < at)
     | . as $i
     | ($i.timelineItems.nodes | map(select(before)) | sort_by(.createdAt)) as $ev
     | (if $asof == "" then [$i.labels.nodes[].name]
        else reduce ($ev[] | select(.__typename == "LabeledEvent" or .__typename == "UnlabeledEvent")) as $e
          ([]; if $e.__typename == "LabeledEvent" then (. + [$e.label.name] | unique) else (. - [$e.label.name]) end) end) as $labels
     | (if $asof == "" then $i.state
        else ([$ev[] | select(.__typename == "ClosedEvent" or .__typename == "ReopenedEvent")] | last | .__typename // "")
          | if . == "ClosedEvent" then "CLOSED" else "OPEN" end end) as $state
     | ([$i.comments.nodes[] | select(before)]) as $comments
     | ((([$i.body] + [$comments[].body]) | join("\n")) | (if $acre == "" then false else test($acre; "i") end)) as $ac
     | (((at | fromdateiso8601) - ($i.createdAt | fromdateiso8601)) / 86400 | floor) as $age
     | ["ISSUE", ($i.number | tostring), $state, ($i.author.login // ""), ($labels | join(", ")),
        ($age | tostring), ($comments | length | tostring), ($ac | tostring)] | @tsv)
' 2>/dev/null) || { echo "error: the PR facts did not parse" >&2; exit 1; }

PR_LINE=$(printf '%s\n' "$FACTS" | awk -F'\t' '$1 == "PR"' | head -1)
IFS=$'\t' read -r _ PR_TITLE IS_FORK PR_AUTHOR <<< "$PR_LINE"
PA_TEAM="contributor"; is_team "$PR_AUTHOR" && PA_TEAM="team"
case "$PR_TITLE" in
  feat:*|feat\(*|feat!*) TITLE_TYPE=feature ;;
  fix:*|fix\(*|fix!*) TITLE_TYPE=fix ;;
  refactor:*|refactor\(*|perf:*) TITLE_TYPE=refactor ;;
  *) TITLE_TYPE=other ;;
esac

FLAGS=""; SKIPPED=""
add_flag() { case " $FLAGS " in *" $1 "*) ;; *) FLAGS="${FLAGS:+$FLAGS }$1" ;; esac; }
# A flag for the process of an outside contributor. A team author gets it as skipped.
add_contributor_flag() {
  if [ "$PA_TEAM" = team ]; then
    case " $SKIPPED " in *" $1 "*) ;; *) SKIPPED="${SKIPPED:+$SKIPPED }$1" ;; esac
  else
    add_flag "$1"
  fi
}

# A breaking change that the author marked. --as-of reads the body as it was then.
if [ -n "$AS_OF" ] && [ -z "$META_FILE" ]; then
  PR_BODY=$(pr_body_as_of "$SLUG" "$NUMBER" "$AS_OF")
else
  PR_BODY=$(printf '%s' "$META" | jq -r '.data.repository.pullRequest.body // ""')
fi
BREAKING=""
BREAKING_TITLE_RE='^[A-Za-z]+(\([^)]*\))?!:'
BREAKING_BODY_RE=$'(^|\n)BREAKING[ -]CHANGE:'
[[ "$PR_TITLE" =~ $BREAKING_TITLE_RE ]] && BREAKING="title"
[[ "$PR_BODY" =~ $BREAKING_BODY_RE ]] && BREAKING="${BREAKING:+$BREAKING and }body"
[ -n "$BREAKING" ] && add_flag behavior-altering

ISSUE_LINES=""
ISSUES=$(printf '%s\n' "$FACTS" | awk -F'\t' '$1 == "ISSUE"')
HAS_AC=false
if [ -n "$ISSUES" ]; then
  while IFS= read -r issue; do
    # A tab is whitespace to read, so an empty field (an issue without labels) would shift
    # the fields after it. The unit separator keeps each empty field.
    IFS=$'\037' read -r _ num state author labels age ncomments ac <<< "${issue//$'\t'/$'\037'}"
    [ -n "$num" ] || continue
    team="contributor"; is_team "$author" && team="team"
    ISSUE_LINES="${ISSUE_LINES}issue: #$num $(printf '%s' "$state" | tr '[:upper:]' '[:lower:]') labels=[$labels] author=$team age=${age}d comments=$ncomments
"
    [ "$ac" = true ] && HAS_AC=true
    has_label "$labels" "$BREAKING_LABELS" && add_flag behavior-altering
    has_label "$labels" "$LOW_IMPACT_LABELS" && add_flag low-impact
    has_label "$labels" "$A11Y_LABELS" && add_flag a11y
    if [ -n "$TRIAGED_LABELS" ] && ! has_label "$labels" "$TRIAGED_LABELS" && [ "$team" != "team" ]; then
      add_flag untriaged
    fi
    [ -n "$PR_AUTHOR" ] && [ "$author" = "$PR_AUTHOR" ] && add_contributor_flag self-filed
  done <<< "$ISSUES"
fi
if [ -n "$AC_PATTERN" ] && [ "$TITLE_TYPE" = feature ] && [ "$HAS_AC" != true ]; then add_contributor_flag feature-no-ac; fi

# ── Verdict hint ──────────────────────────────────────────────────────
has() { case " $FLAGS " in *" $1 "*) return 0 ;; esac; return 1; }
VERDICT="take"; REASONS=""
add_reason() { REASONS="${REASONS}verdict_reason: $1
"; }
if has behavior-altering; then VERDICT=decide; add_reason "behavior-altering -> question (semver)"; fi
if has feature-no-ac; then VERDICT=decide; add_reason "feature-no-ac -> question (design)"; fi
if has low-impact && [ "$REACH_MAX" -ge "$REACH_DECIDE" ]; then VERDICT=decide; add_reason "low-impact and reach $REACH_MAX -> question (design)"; fi
if has a11y && [ "$REACH_MAX" -ge "$REACH_DECIDE" ]; then VERDICT=decide; add_reason "a11y and reach $REACH_MAX -> question (a11y)"; fi
if [ "$VERDICT" = take ] && { has untriaged || has self-filed; }; then
  VERDICT=review; add_reason "$(has untriaged && echo untriaged)$(has untriaged && has self-filed && echo ' and ')$(has self-filed && echo self-filed) -> confirm the bug on base first"
fi

# ── Print ─────────────────────────────────────────────────────────────
echo "=== SCREENING ==="
echo "fork: ${IS_FORK:-unknown}"
echo "pr_author: ${PR_AUTHOR:-unknown} ($PA_TEAM)"
echo "screening_config: ${CONFIG:-none (generic rules only)}"
echo "title_type: $TITLE_TYPE"
[ -n "$AS_OF" ] && echo "as_of: $AS_OF"
if [ -n "$ISSUE_LINES" ]; then printf '%s' "$ISSUE_LINES"; else echo "issue: none linked with a closing keyword"; fi
echo "issue_flags: ${FLAGS:-none}"
[ -n "$SKIPPED" ] && echo "skipped_flags: $SKIPPED (team author)"
[ -n "$BREAKING" ] && echo "breaking_marker: $BREAKING"
echo "verdict_hint: $VERDICT"
# The first option of the pr-review Gate for the hint (skills/pr-review/SKILL.md, Gate).
case "$VERDICT" in
  take) if [ "$SCALE" = trivial ]; then GATE="Quick review"; else GATE="Full review"; fi ;;
  review) GATE="Full review" ;;
  *) GATE="Draft a reply" ;;
esac
echo "gate_default: $GATE"
printf '%s' "$REASONS"
