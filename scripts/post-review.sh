#!/usr/bin/env bash
# post-review.sh — Post the findings of a review run as ONE GitHub review.
#
# Requires the `gh` CLI (authenticated) and `jq`. Fails loudly without them.
#
# Usage:
#   post-review.sh [--pr <number-or-url>] --head <sha> --findings <file.json> [--summary <file.md>]
#                  [--body-only] [--dry-run]
#
# <file.json>:
#   {"findings": [{"file": "path/in/diff", "line": 42, "message": "**issue (logic, blocking):** ...",
#                  "allow_nearby": false}]}
#   `line` may be null (file-level). `file` may be null (review body only). Every
#   message must open with a Conventional Comments label (lib/conventional-label.sh).
#   One bad message refuses the whole batch before any network call.
# <sha>: the full head SHA that the review read (the plan's `head:`). When the PR head
#   moved since, the script refuses if a commented file differs between the two heads.
# <file.md>: optional text for the review body: what clearing the findings earns. The script writes the census itself.
#
# Each finding becomes its own review thread, anchored try-then-demote: a line
# thread, then a file thread, then a block in the review body. GitHub judges the
# anchor (a line outside the diff, a deleted or binary file), so any failure
# demotes and nothing breaks the review. The body holds one census line by label,
# the summary, and only the findings that no thread could hold — the threads carry
# the rest, so the body never repeats them. It ends with a hidden marker that
# records the reviewed head SHA. The review is built pending and submitted once,
# so the author gets one notification, not one per finding (the same flow as the
# upstream vaadin/github-actions code-review action).
#
# --body-only puts every finding in the review body, blocking first, each under its
# `file:line`. It is the one-comment rendering for a fork PR (skills/pr-review step 6):
# the author gets one list to work through, and no thread is opened.
#
# A line finding within two lines of an existing thread root on the same file is
# skipped and listed: reply into that thread with `post-comment.sh --reply <id>`,
# or set "allow_nearby": true when the claim is genuinely different.
#
# The :robot: AI-generated prefix opens the body and every thread.
#
# Prints one line per finding (`line:`, `file:`, `body:` or `skipped:`), a posted thread
# with its URL, then the review URL. Exit codes: 0 posted (or dry run), 1 an API failure,
# 2 a usage or validation error.
set -euo pipefail

PR=""
FINDINGS=""
SUMMARY=""
REVIEWED_HEAD=""
DRY_RUN=false
BODY_ONLY=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --pr) PR="${2:?--pr requires a value}"; shift 2 ;;
    --head) REVIEWED_HEAD="${2:?--head requires a value}"; shift 2 ;;
    --findings) FINDINGS="${2:?--findings requires a value}"; shift 2 ;;
    --summary) SUMMARY="${2:?--summary requires a value}"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    --body-only) BODY_ONLY=true; shift ;;
    --help|-h) sed -n '2,/^set -euo pipefail$/{/^set /d;p;}' "$0"; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done

for tool in gh jq; do
  command -v "$tool" >/dev/null 2>&1 || { echo "error: $tool not found — this script requires it" >&2; exit 1; }
done
[ -n "$FINDINGS" ] || { echo "error: --findings is required" >&2; exit 2; }
[ -f "$FINDINGS" ] || { echo "error: findings file not found: $FINDINGS" >&2; exit 2; }
if [ -n "$SUMMARY" ] && [ ! -f "$SUMMARY" ]; then
  echo "error: summary file not found: $SUMMARY" >&2; exit 2
fi
jq -e '.findings | type == "array"' "$FINDINGS" >/dev/null 2>&1 || {
  echo "error: $FINDINGS must be a JSON object with a \"findings\" array" >&2; exit 2
}
# The line numbers of the findings belong to the head that the review read. Without
# it, the script cannot tell whether the PR moved under the anchors.
[[ "$REVIEWED_HEAD" =~ ^[0-9a-f]{40}$ ]] || {
  echo "error: --head <sha> is required: the full 40-character SHA that the review read (the plan's head:)" >&2; exit 2
}

# shellcheck source=lib/conventional-label.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/conventional-label.sh"

N=$(jq '.findings | length' "$FINDINGS")
field() { jq -r --argjson i "$1" ".findings[\$i].$2 // empty" "$FINDINGS"; }

# ── Validate every message before any network call ───────────────────
for ((i = 0; i < N; i++)); do
  msg=$(field "$i" message)
  [ -n "$msg" ] || { echo "error: finding $i has no message" >&2; exit 2; }
  check_conventional_label "$msg" || { echo "error: finding $i refused, nothing posted" >&2; exit 2; }
  line=$(field "$i" line)
  if [ -n "$line" ] && ! [[ "$line" =~ ^[0-9]+$ ]]; then
    echo "error: finding $i has a non-integer line: $line" >&2; exit 2
  fi
done

# ── Resolve the PR and its own repo ──────────────────────────────────
PR_ARGS=()
[ -n "$PR" ] && PR_ARGS+=("$PR")
PR_JSON=$(gh pr view ${PR_ARGS[@]+"${PR_ARGS[@]}"} --json id,number,headRefOid,url 2>/dev/null) || {
  echo "error: failed to resolve the PR — pass --pr <number-or-url>, or check gh authentication" >&2; exit 1
}
PR_ID=$(printf '%s' "$PR_JSON" | jq -r .id)
PR_NUMBER=$(printf '%s' "$PR_JSON" | jq -r .number)
HEAD_SHA=$(printf '%s' "$PR_JSON" | jq -r .headRefOid)
PR_URL=$(printf '%s' "$PR_JSON" | jq -r .url)
REPO_SLUG=$(printf '%s' "$PR_URL" | sed -n 's|^https://[^/]*/\([^/]*/[^/]*\)/pull/.*|\1|p')
[ -n "$REPO_SLUG" ] || { echo "error: could not derive the repo from $PR_URL" >&2; exit 1; }

# ── The PR head must still match the reviewed head on every commented file ──
# A push after the review (a rebase, a fixup) can shift the lines under the anchors.
# Refuse when a commented file differs; a move that leaves them alone is harmless.
if [ "$REVIEWED_HEAD" != "$HEAD_SHA" ]; then
  for sha in "$REVIEWED_HEAD" "$HEAD_SHA"; do
    git cat-file -e "$sha^{commit}" 2>/dev/null \
      || git fetch -q --no-tags "https://github.com/$REPO_SLUG.git" "$sha" 2>/dev/null || true
    git cat-file -e "$sha^{commit}" 2>/dev/null || {
      echo "error: the PR head moved from ${REVIEWED_HEAD:0:7} to ${HEAD_SHA:0:7}, and commit ${sha:0:7} is not available — run from a clone of $REPO_SLUG; nothing posted" >&2
      exit 2
    }
  done
  COMMENTED=()
  while IFS= read -r f; do [ -n "$f" ] && COMMENTED+=("$f"); done < <(jq -r '.findings[].file // empty' "$FINDINGS" | sort -u)
  MOVED=""
  [ "${#COMMENTED[@]}" -gt 0 ] && MOVED=$(git diff --name-only "$REVIEWED_HEAD" "$HEAD_SHA" -- "${COMMENTED[@]}")
  if [ -n "$MOVED" ]; then
    echo "error: the PR head moved from ${REVIEWED_HEAD:0:7} to ${HEAD_SHA:0:7}, and these commented files changed:" >&2
    printf '  %s\n' $MOVED >&2
    echo "re-run the review on ${HEAD_SHA:0:7}; nothing posted" >&2
    exit 2
  fi
  echo "note: the PR head moved from ${REVIEWED_HEAD:0:7} to ${HEAD_SHA:0:7}; no commented file changed, so the anchors hold"
fi

# Thread roots already on the PR, for the nearby guard.
ROOTS=$(gh api "repos/$REPO_SLUG/pulls/$PR_NUMBER/comments" --paginate \
  --jq '.[] | select(.in_reply_to_id == null) | [.id, .path, (.line // .original_line // 0)] | @tsv' 2>/dev/null || true)

nearby() {  # nearby <path> <line> — ids of thread roots within two lines
  printf '%s\n' "$ROOTS" | awk -F'\t' -v p="$1" -v l="$2" '
    $2 == p { d = $3 - l; if (d < 0) d = -d; if (d <= 2) printf "%s ", $1 }'
}

PREFIX=":robot: AI-generated"

# ── GraphQL (pending-review flow) ────────────────────────────────────
Q_PENDING='query($owner:String!,$name:String!,$number:Int!){repository(owner:$owner,name:$name){pullRequest(number:$number){reviews(states:PENDING,first:10){nodes{id}}}}}'
M_DELETE='mutation($reviewId:ID!){deletePullRequestReview(input:{pullRequestReviewId:$reviewId}){pullRequestReview{id}}}'
M_ADD_PENDING='mutation($prId:ID!){addPullRequestReview(input:{pullRequestId:$prId}){pullRequestReview{id}}}'
M_LINE='mutation($reviewId:ID!,$path:String!,$line:Int!,$body:String!){addPullRequestReviewThread(input:{pullRequestReviewId:$reviewId,path:$path,line:$line,side:RIGHT,subjectType:LINE,body:$body}){thread{id comments(first:1){nodes{url}}}}}'
M_FILE='mutation($reviewId:ID!,$path:String!,$body:String!){addPullRequestReviewThread(input:{pullRequestReviewId:$reviewId,path:$path,subjectType:FILE,body:$body}){thread{id comments(first:1){nodes{url}}}}}'
M_SUBMIT='mutation($reviewId:ID!,$body:String!){submitPullRequestReview(input:{pullRequestReviewId:$reviewId,event:COMMENT,body:$body}){pullRequestReview{url}}}'
M_BODY_ONLY='mutation($prId:ID!,$body:String!){addPullRequestReview(input:{pullRequestId:$prId,event:COMMENT,body:$body}){pullRequestReview{url}}}'

# A failed thread is a GraphQL error OR a 200 with thread: null — GitHub reports a
# line outside the diff the second way.
# Sets THREAD_URL to the URL of the first comment of the new thread.
THREAD_JQ='.data.addPullRequestReviewThread.thread // empty | "\(.id) \(.comments.nodes[0].url // "")"'
add_thread() {  # add_thread <line|file> <path> <line> <body>
  local out
  if [ "$1" = line ]; then
    out=$(gh api graphql -f query="$M_LINE" -f reviewId="$REVIEW_ID" -f path="$2" -F line="$3" -f body="$4" \
      --jq "$THREAD_JQ" 2>/dev/null || true)
  else
    out=$(gh api graphql -f query="$M_FILE" -f reviewId="$REVIEW_ID" -f path="$2" -f body="$4" \
      --jq "$THREAD_JQ" 2>/dev/null || true)
  fi
  THREAD_URL="${out#* }"
  [ -n "$out" ]
}

# census — "4 issues (**2 blocking**), 7 suggestions" from one "<label> [blocking]"
# line per posted finding, in the order of the closed vocabulary (references/severity.md).
census() {
  printf '%s\n' "$1" | awk '
    NF { n[$1]++; if ($2 == "blocking") b[$1]++ }
    END {
      k = split("issue suggestion todo question chore nitpick thought", order, " ")
      for (i = 1; i <= k; i++) seen[order[i]] = 1
      for (w in n) if (!(w in seen)) order[++k] = w
      for (i = 1; i <= k; i++) {
        w = order[i]
        if (!(w in n)) continue
        part = n[w] " " w (n[w] > 1 ? "s" : "")
        if (w in b) part = part " (**" b[w] " blocking**)"
        out = out (out == "" ? "" : ", ") part
      }
      print out
    }'
}
BLOCKING_RE='[(, ]blocking[),]'

# ── Build the threads ────────────────────────────────────────────────
REVIEW_ID=""
SUBMITTED=false
cleanup() {
  if [ -n "$REVIEW_ID" ] && [ "$SUBMITTED" != true ]; then
    gh api graphql -f query="$M_DELETE" -f reviewId="$REVIEW_ID" >/dev/null 2>&1 || true
    echo "warn: the pending review was deleted, nothing posted" >&2
  fi
}
trap cleanup EXIT

if [ "$DRY_RUN" != true ] && [ "$N" -gt 0 ] && [ "$BODY_ONLY" != true ]; then
  STALE=$(gh api graphql -f query="$Q_PENDING" -f owner="${REPO_SLUG%%/*}" -f name="${REPO_SLUG##*/}" -F number="$PR_NUMBER" \
    --jq '.data.repository.pullRequest.reviews.nodes[].id' 2>/dev/null || true)
  # Pending reviews are visible to their author only, so each one is a leftover of ours.
  for id in $STALE; do
    gh api graphql -f query="$M_DELETE" -f reviewId="$id" >/dev/null 2>&1 || true
    echo "warn: deleted a stale pending review ($id)" >&2
  done
  REVIEW_ID=$(gh api graphql -f query="$M_ADD_PENDING" -f prId="$PR_ID" \
    --jq '.data.addPullRequestReview.pullRequestReview.id' 2>/dev/null || true)
  [ -n "$REVIEW_ID" ] || { echo "error: could not create a pending review" >&2; exit 1; }
fi

KINDS=""
UNANCHORED=""
INLINE=0
BODY_N=0
SKIPPED=0
ORDER=""
if [ "$BODY_ONLY" = true ]; then
  # Blocking findings first, then the rest, each group in the order of the file.
  for ((i = 0; i < N; i++)); do
    first=$(field "$i" message | head -1)
    [[ "$first" =~ $BLOCKING_RE ]] && ORDER="$ORDER $i"
  done
  for ((i = 0; i < N; i++)); do
    case " $ORDER " in *" $i "*) ;; *) ORDER="$ORDER $i" ;; esac
  done
else
  for ((i = 0; i < N; i++)); do ORDER="$ORDER $i"; done
fi
for i in $ORDER; do
  msg=$(field "$i" message)
  file=$(field "$i" file)
  line=$(field "$i" line)
  allow=$(field "$i" allow_nearby)
  first="${msg%%$'\n'*}"
  label=$(printf '%s' "$first" | sed -n 's/^\*\*\([^*]*\):\*\* .*/\1/p')
  where="${file:-}${line:+:$line}"

  if [ "$BODY_ONLY" != true ] && [ -n "$file" ] && [ -n "$line" ] && [ "$allow" != true ]; then
    near=$(nearby "$file" "$line")
    if [ -n "$near" ]; then
      echo "skipped: $where (existing thread ${near% } — reply into it with post-comment.sh --reply)"
      SKIPPED=$((SKIPPED + 1))
      continue
    fi
  fi
  kind="${label%% *}"
  [[ "$label" =~ $BLOCKING_RE ]] && kind="$kind blocking"
  KINDS="$KINDS
$kind"

  thread_body="$PREFIX

$msg"
  if [ "$BODY_ONLY" = true ]; then
    file=""; line=""
  fi
  if [ "$DRY_RUN" = true ] && [ -n "$file" ]; then
    printf -- '--- thread %s ---\n%s\n\n' "$where" "$thread_body"
    INLINE=$((INLINE + 1))
    continue
  fi
  if [ -n "$file" ] && [ -n "$line" ] && add_thread line "$file" "$line" "$thread_body"; then
    echo "line: $where${THREAD_URL:+ $THREAD_URL}"; INLINE=$((INLINE + 1)); continue
  fi
  if [ -n "$file" ]; then
    file_body="$thread_body"
    [ -n "$line" ] && file_body="$PREFIX

_About line $line._

$msg"
    if add_thread file "$file" "" "$file_body"; then
      echo "file: $where${THREAD_URL:+ $THREAD_URL}"; INLINE=$((INLINE + 1)); continue
    fi
  fi
  [ "$BODY_ONLY" = true ] || echo "body: ${where:-(no anchor)}"
  [ "$BODY_ONLY" = true ] && echo "body: ${where:-(no anchor)} (--body-only)"
  BODY_N=$((BODY_N + 1))
  loc=""
  [ -n "$where" ] && loc="**\`$where\`**

"
  UNANCHORED="$UNANCHORED

$loc$msg"
done

# ── Review body ──────────────────────────────────────────────────────
POSTED=$((INLINE + BODY_N))
if [ "$POSTED" -eq 0 ] && [ "$SKIPPED" -gt 0 ]; then
  echo "posted: nothing — every finding sits next to an existing thread ($SKIPPED skipped)"
  exit 0
fi
if [ "$POSTED" -eq 0 ]; then
  OVERVIEW="Reviewed \`${REVIEWED_HEAD:0:7}\`. Nothing to flag."
else
  OVERVIEW="Reviewed \`${REVIEWED_HEAD:0:7}\` and left $POSTED comment$([ "$POSTED" -eq 1 ] || echo s): $(census "$KINDS")."
  if [ "$BODY_ONLY" = true ]; then
    OVERVIEW="Reviewed \`${REVIEWED_HEAD:0:7}\`: $(census "$KINDS"). Each point is below, blocking first."
  elif [ "$BODY_N" -eq 1 ]; then
    OVERVIEW="$OVERVIEW One of them is below, because it could not be attached to the diff."
  elif [ "$BODY_N" -gt 1 ]; then
    OVERVIEW="$OVERVIEW $BODY_N of them are below, because they could not be attached to the diff."
  fi
fi
BODY="$PREFIX

$OVERVIEW"
[ -n "$SUMMARY" ] && BODY="$BODY

$(cat "$SUMMARY")"
[ -n "$UNANCHORED" ] && BODY="$BODY$UNANCHORED"
BODY="$BODY

<!-- agent-skills:reviewed-head $REVIEWED_HEAD -->"

if [ "$DRY_RUN" = true ]; then
  printf -- '--- review body ---\n%s\n' "$BODY"
  echo "dry run: $POSTED findings, $SKIPPED skipped, nothing posted"
  exit 0
fi

if [ -n "$REVIEW_ID" ]; then
  URL=$(gh api graphql -f query="$M_SUBMIT" -f reviewId="$REVIEW_ID" -f body="$BODY" \
    --jq '.data.submitPullRequestReview.pullRequestReview.url' 2>/dev/null || true)
else
  URL=$(gh api graphql -f query="$M_BODY_ONLY" -f prId="$PR_ID" -f body="$BODY" \
    --jq '.data.addPullRequestReview.pullRequestReview.url' 2>/dev/null || true)
fi
[ -n "$URL" ] || { echo "error: could not submit the review" >&2; exit 1; }
SUBMITTED=true
echo "posted: $INLINE threads, $BODY_N in the body, $SKIPPED skipped"
echo "review: $URL"
