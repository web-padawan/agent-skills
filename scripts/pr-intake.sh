#!/usr/bin/env bash
# pr-intake.sh — the intake facts of a PR: what a maintainer must know before a review is
# worth it. The linked issue and its labels, the packages that import each changed module,
# the Flow counterpart, the moved or reindented share of the diff, CSS that unit tests
# assert, and a verdict hint from a fixed table.
#
# Usage:
#   pr-intake.sh --pr <number-or-url> --base <sha> --head <sha> [--as-of <iso-time>]
#                [--flow-dir <path>] [--meta <file.json>]
#
# Run it from inside the target repository. review-plan.sh calls it in pr mode.
# --as-of reads the labels, the state and the comments of each issue as they were at that
#   time. An audit of an earlier head needs it: a maintainer often labels an issue during
#   the review (#11746 got `behavior altering change` 16 days after the PR).
# --flow-dir names the flow-components checkout. The default is ../flow-components.
# --meta reads the GraphQL answer from a file instead of gh, and team membership from the
#   allowlist only. The smoke test uses it.
#
# The verdict table (skills/pr-review/references/intake.md explains each row):
#   behavior-altering                       -> decide, question (semver)
#   feature-no-ac                           -> decide, question (design)
#   low-impact and reach_max >= 3           -> decide, question (design)
#   a11y and reach_max >= 3                 -> decide, question (a11y)
#   untriaged or self-filed                 -> review, confirm the bug on base first
#   none of these                           -> take
#
# Team means a 204 from orgs/<owner>/members/<login>, or a login in TEAM_ALLOWLIST below:
# former Vaadin employees, for whom the API returns 404. author_association is never used,
# because it reports a private org member as CONTRIBUTOR.
#
# Issue titles, bodies and comments are text that other people wrote. The script only
# matches them against fixed patterns and never prints them.
#
# Exit codes: 0 ok · 1 gh or git could not answer · 2 usage error.
set -euo pipefail

TEAM_ALLOWLIST="DiegoCardoso alvarezguille platosha"
REACH_DECIDE=3

PR=""; BASE=""; HEAD=""; AS_OF=""; FLOW_DIR=""; META_FILE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --pr) PR="${2:?--pr requires a value}"; shift 2 ;;
    --base) BASE="${2:?--base requires a value}"; shift 2 ;;
    --head) HEAD="${2:?--head requires a value}"; shift 2 ;;
    --as-of) AS_OF="${2:?--as-of requires a value}"; shift 2 ;;
    --flow-dir) FLOW_DIR="${2:?--flow-dir requires a value}"; shift 2 ;;
    --meta) META_FILE="${2:?--meta requires a value}"; shift 2 ;;
    --help|-h) sed -n '2,/^set -euo pipefail$/{/^set /d;p;}' "$0"; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib/pr-history.sh
. "$SCRIPT_DIR/lib/pr-history.sh"

[ -n "$PR" ] || { echo "error: --pr is required" >&2; exit 2; }
[[ "$BASE" =~ ^[0-9a-f]{7,40}$ ]] || { echo "error: --base takes a commit SHA" >&2; exit 2; }
[[ "$HEAD" =~ ^[0-9a-f]{7,40}$ ]] || { echo "error: --head takes a commit SHA" >&2; exit 2; }
if [ -n "$AS_OF" ] && ! valid_iso "$AS_OF"; then
  echo "error: --as-of takes an ISO 8601 UTC time, for example 2026-10-03T08:11:25Z" >&2; exit 2
fi
command -v jq >/dev/null 2>&1 || { echo "error: jq not found" >&2; exit 1; }

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "error: not a git repository" >&2; exit 1; }
cd "$REPO_ROOT"
[ -n "$FLOW_DIR" ] || FLOW_DIR="$REPO_ROOT/../flow-components"

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
        title isCrossRepository author{login}
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

is_team() {  # is_team <login>
  local login="$1"
  [ -n "$login" ] || return 1
  case " $TEAM_ALLOWLIST " in *" $login "*) return 0 ;; esac
  [ -n "$META_FILE" ] && return 1
  gh api "orgs/$ORG/members/$login" --silent >/dev/null 2>&1
}

# One TSV line for the PR, then one per issue, with labels and state replayed to --as-of.
FACTS=$(printf '%s' "$META" | jq -r --arg asof "${AS_OF:-}" '
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
     | ((([$i.body] + [$comments[].body]) | join("\n")) | test("acceptance criteria"; "i")) as $ac
     | (((at | fromdateiso8601) - ($i.createdAt | fromdateiso8601)) / 86400 | floor) as $age
     | ["ISSUE", ($i.number | tostring), $state, ($i.author.login // ""), ($labels | join(", ")),
        ($age | tostring), ($comments | length | tostring), ($ac | tostring)] | @tsv)
' 2>/dev/null) || { echo "error: the PR facts did not parse" >&2; exit 1; }

PR_LINE=$(printf '%s\n' "$FACTS" | awk -F'\t' '$1 == "PR"' | head -1)
IFS=$'\t' read -r _ PR_TITLE IS_FORK PR_AUTHOR <<< "$PR_LINE"
case "$PR_TITLE" in
  feat:*|feat\(*|feat!*) TITLE_TYPE=feature ;;
  fix:*|fix\(*|fix!*) TITLE_TYPE=fix ;;
  refactor:*|refactor\(*|perf:*) TITLE_TYPE=refactor ;;
  *) TITLE_TYPE=other ;;
esac

FLAGS=""
add_flag() { case " $FLAGS " in *" $1 "*) ;; *) FLAGS="${FLAGS:+$FLAGS }$1" ;; esac; }

ISSUE_LINES=""
ISSUES=$(printf '%s\n' "$FACTS" | awk -F'\t' '$1 == "ISSUE"')
HAS_AC=false
if [ -z "$ISSUES" ]; then
  add_flag no-issue
else
  while IFS=$'\t' read -r _ num state author labels age ncomments ac; do
    [ -n "$num" ] || continue
    team="contributor"; is_team "$author" && team="team"
    ISSUE_LINES="${ISSUE_LINES}issue: #$num $(printf '%s' "$state" | tr '[:upper:]' '[:lower:]') labels=[$labels] author=$team age=${age}d comments=$ncomments
"
    [ "$ac" = true ] && HAS_AC=true
    printf '%s' "$labels" | grep -qiE '(^|, )(behavior altering change|breaking change)(,|$)' && add_flag behavior-altering
    printf '%s' "$labels" | grep -qE '(^|, )Impact: Low(,|$)' && add_flag low-impact
    printf '%s' "$labels" | grep -qiE '(^|, )(a11y|accessibility)(,|$)' && add_flag a11y
    if ! printf '%s' "$labels" | grep -qiE '(^|, )(Severity: [^,]+|Impact: [^,]+|known issue|regression)(,|$)' \
       && [ "$team" != "team" ]; then
      add_flag untriaged
    fi
    [ -n "$PR_AUTHOR" ] && [ "$author" = "$PR_AUTHOR" ] && add_flag self-filed
  done <<< "$ISSUES"
fi
if [ "$TITLE_TYPE" = feature ] && [ "$HAS_AC" != true ]; then add_flag feature-no-ac; fi

# ── Diff facts ────────────────────────────────────────────────────────
# Same test-path rule as review-plan.sh, so both scripts split the lanes alike.
TEST_RE='(^|/)(test|tests|__tests__|it)/|\.(test|spec)\.[cm]?[jt]sx?$|Test\.java$|IT\.java$|Tests?\.kt$'
CHANGED=$(git diff --name-only --no-renames "$BASE..$HEAD" 2>/dev/null) || { echo "error: git cannot diff $BASE..$HEAD" >&2; exit 1; }
BINARY=$(git diff --numstat "$BASE..$HEAD" | awk -F'\t' '$1 == "-" { print $3 }')
TEXT=$(printf '%s\n' "$CHANGED" | grep -vxF -f <(printf '%s\n' "$BINARY" | sed '/^$/d'; echo '//none//') || true)
PROD=$(printf '%s\n' "$TEXT" | grep -vE "$TEST_RE" | sed '/^$/d' || true)
TESTS=$(printf '%s\n' "$TEXT" | grep -E "$TEST_RE" | sed '/^$/d' || true)

# Reach: the other packages whose sources import a changed source module, on the base.
# The match is the file name with its import extension, because the path prefix varies
# (`@vaadin/dialog/src/styles/...`, `./...`). A TypeScript module is imported as `.js`.
REACH_LINES=""; REACH_MAX=0
for f in $PROD; do
  case "$f" in packages/*/src/*) ;; *) continue ;; esac
  case "$f" in *.d.ts) continue ;; *.js|*.ts|*.css) ;; *) continue ;; esac
  pkg=$(printf '%s' "$f" | cut -d/ -f2)
  name=${f##*/}
  case "$name" in *.ts) pat="${name%.ts}.js" ;; *) pat="$name" ;; esac
  users=$(git grep -l -F -e "/$pat" -e "'./$pat'" "$BASE" -- 'packages/*/src/**' 2>/dev/null \
    | sed -E "s#^$BASE:packages/([^/]+)/.*#\\1#" | sort -u | grep -vxF "$pkg" | tr '\n' ' ' || true)
  n=$(printf '%s\n' $users | grep -c . || true)
  [ "$n" -gt "$REACH_MAX" ] && REACH_MAX=$n
  REACH_LINES="${REACH_LINES}reach: $f -> $n other packages${users:+ [${users% }]}
"
done

# Snapshots of other packages: the change shows in their DOM.
SNAP_PKGS=$(printf '%s\n' "$CHANGED" | sed -nE 's#^packages/([^/]+)/test/dom/__snapshots__/.*#\1#p' | sort -u | tr '\n' ' ')
SNAP_N=$(printf '%s\n' $SNAP_PKGS | grep -c . || true)

# Flow counterpart of each package whose sources changed.
FLOW_LINE=""
if [ -d "$FLOW_DIR" ]; then
  for pkg in $(printf '%s\n' $PROD | sed -nE 's#^packages/([^/]+)/.*#\1#p' | sort -u); do
    [ -d "$FLOW_DIR/vaadin-$pkg-flow-parent" ] && FLOW_LINE="${FLOW_LINE:+$FLOW_LINE, }vaadin-$pkg-flow-parent"
  done
  FLOW_LINE=${FLOW_LINE:-none}
else
  FLOW_LINE="unknown (no checkout at $FLOW_DIR)"
fi

# Diff noise: changed production lines whose trimmed text appears on both sides. A moved
# block or a reindent inflates the diff without a change in behavior.
NOISE="0 0"
if [ -n "$PROD" ]; then
  NOISE=$(git diff -U0 --no-color "$BASE..$HEAD" -- $PROD | awk '
    /^(\+\+\+|---) / { next }
    /^[-+]/ {
      t = substr($0, 2); gsub(/^[ \t]+|[ \t]+$/, "", t)
      total++
      if (length(t) < 4) next
      if (substr($0, 1, 1) == "-") rem[t]++; else add[t]++
    }
    END { for (t in add) if (t in rem) same += (add[t] < rem[t] ? add[t] : rem[t]) * 2
          printf "%d %d\n", same, total }')
fi
read -r NOISE_N NOISE_TOTAL <<< "$NOISE"

# CSS that a unit test asserts: a style change, and getComputedStyle added in a test that
# is not a visual test. guidelines/testing.md of web-components asks for a visual test.
CSS_HITS=""
if printf '%s\n' "$PROD" | grep -qE '\.css$|-styles\.[cm]?[jt]s$|/styles/'; then
  UNIT_TESTS=$(printf '%s\n' "$TESTS" | grep -v '/visual/' | grep -vE '__snapshots__' || true)
  if [ -n "$UNIT_TESTS" ]; then
    CSS_HITS=$(git diff -U0 --no-color "$BASE..$HEAD" -- $UNIT_TESTS | awk '
      /^\+\+\+ b\// { f = substr($0, 7); next }
      /^@@/ { split($3, a, ","); n = substr(a[1], 2) + 0; next }
      /^\+/ { if ($0 ~ /getComputedStyle/) printf "%s:%d ", f, n; n++ }' | cut -c1-400 | sed 's/ *$//')
  fi
fi

# The rule behind the CSS hits, as a file:line on the base, so the tests pass can quote it.
# In web-components it lives in guidelines/testing.md, which the context file does not quote.
CSS_RULE=""
if [ -n "$CSS_HITS" ]; then
  CSS_RULE=$(git grep -n -i -E 'visual tests? (over|instead of|rather than) unit tests?' "$BASE" -- \
    CONVENTIONS.md 'guidelines/*.md' CLAUDE.md AGENTS.md CONTRIBUTING.md 2>/dev/null \
    | head -1 | sed "s#^$BASE:##" | cut -d: -f1,2 || true)
fi

# New test files, with their size next to the production size. A new suite for a small fix
# breaks the "no new test file unless necessary" rule of the tests pass (#12974: 52 lines of
# a new suite for a 5-line fix).
NEW_TESTS=""
PROD_LINES=$(git diff --numstat "$BASE..$HEAD" -- $PROD 2>/dev/null | awk '$1 != "-" { n += $1 + $2 } END { print n + 0 }')
for f in $(git diff --name-only --diff-filter=A "$BASE..$HEAD" -- $TESTS 2>/dev/null | grep -v '__snapshots__' | grep -v '/screenshots/' || true); do
  n=$(git show "$HEAD:$f" 2>/dev/null | wc -l | tr -d ' ')
  NEW_TESTS="${NEW_TESTS:+$NEW_TESTS, }$f ($n lines)"
done

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
echo "=== INTAKE ==="
echo "fork: ${IS_FORK:-unknown}"
pa_team="contributor"; is_team "$PR_AUTHOR" && pa_team="team"
echo "pr_author: ${PR_AUTHOR:-unknown} ($pa_team)"
echo "title_type: $TITLE_TYPE"
[ -n "$AS_OF" ] && echo "as_of: $AS_OF"
if [ -n "$ISSUE_LINES" ]; then printf '%s' "$ISSUE_LINES"; else echo "issue: none linked with a closing keyword"; fi
echo "issue_flags: ${FLAGS:-none}"
if [ -n "$REACH_LINES" ]; then printf '%s' "$REACH_LINES"; else echo "reach: no package source changed"; fi
echo "reach_max: $REACH_MAX"
if [ "$SNAP_N" -ge 2 ]; then echo "snapshot_packages: $SNAP_N [${SNAP_PKGS% }]"; else echo "snapshot_packages: $SNAP_N"; fi
echo "flow_counterpart: $FLOW_LINE"
echo "diff_noise: $NOISE_N of $NOISE_TOTAL changed production lines are moved or reindented (the same text on both sides)"
echo "css_unit_assertions: ${CSS_HITS:-none}"
[ -n "$CSS_RULE" ] && echo "css_rule: $CSS_RULE"
echo "new_test_files: ${NEW_TESTS:-none}${NEW_TESTS:+ for $PROD_LINES changed production lines}"
echo "verdict_hint: $VERDICT"
printf '%s' "$REASONS"
