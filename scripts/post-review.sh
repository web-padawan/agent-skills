#!/usr/bin/env bash
# post-review.sh — Post the findings of a review run as ONE GitHub review.
#
# Requires the `gh` CLI (authenticated) and `jq`. Fails loudly without them.
#
# Usage:
#   post-review.sh [--pr <number-or-url>] --head <sha> --findings <file.json> [--summary <file.md>]
#                  [--body-only] [--blocking-only] [--dry-run]
#
# <file.json>: the frozen list of triage (pipeline.md §5.7), one object per finding:
#   {"findings": [{"file": "path/in/diff", "line": 42, "message": "**issue (logic, blocking):** ...",
#                  "status": "confirmed", "dup": {"id": 123, "verdict": "contradicts"},
#                  "summary_only": false, "allow_nearby": false}]}
#   `line` may be null (file-level). `file` may be null (review body only). Every
#   message must open with a Conventional Comments label (lib/conventional-label.sh).
#   `status` is `confirmed` (the default), `accepted`, `already raised`, `dismissed`,
#   `fixed` or `dropped`, with any note after the word. Only the first two post as a new
#   thread. `dup` names the thread of `## Already on the PR` that makes the same claim, with
#   the verdict of triage: `confirms` never posts, `contradicts` and `not fixed` post the
#   message as a reply into that thread, inside the same review. `summary_only` puts the
#   finding in the review body. One bad field refuses the whole batch before any network call.
#   The script lists every finding that it does not post, with the reason.
# <sha>: the full head SHA that the review read (the plan's `head:`). When the PR head
#   moved since, the script refuses if a commented file differs between the two heads.
# <file.md>: optional text for the review body: what clearing the findings earns. The script writes the census itself.
#
# Each finding becomes its own review thread, anchored try-then-demote: a line
# thread, then a file thread, then a block in the review body. GitHub judges the
# anchor (a line outside the diff, a deleted or binary file), so any failure
# demotes and nothing breaks the review. The body holds one census line by label,
# the summary, and only the findings that no thread could hold — the threads carry
# the rest, so the body never repeats them. The review is built pending and submitted once,
# so the author gets one notification, not one per finding (the same flow as the
# upstream vaadin/github-actions code-review action).
#
# --body-only puts every finding in the review body, blocking first, each under its
# `file:line`. It is the one-comment rendering for a fork PR (the Present step of pr-review):
# the author gets one list to work through, and no new thread is opened. A reply still goes
# into its thread.
#
# --blocking-only posts only the findings whose label carries `blocking`, and lists the rest.
# It refuses the run when no finding is blocking.
#
# A line finding must sit on a line of a hunk of the PR diff, context lines included.
# GitHub moves a thread on any other line to the file, so the script refuses the batch
# before anything posts, also in a dry run. Re-anchor such a finding, or set
# "summary_only": true. A file that the PR diff shows without a patch (a binary or a very
# large file) is not checked.
#
# A line finding within two lines of an existing thread root on the same file is
# skipped and listed. Triage the thread first (pipeline.md §5.2), then reply into it with
# `post-comment.sh --reply <id>`, or set "allow_nearby": true when the claim is genuinely different.
#
# The :robot: AI-generated prefix opens the body and every thread.
#
# Prints one line per finding (`line:`, `file:`, `reply:`, `body:` or `skipped:`), a posted
# thread or reply with its URL, then the review URL. Exit codes: 0 posted (or dry run), 1 an API failure,
# 2 a usage or validation error.
set -euo pipefail

PR=""
FINDINGS=""
SUMMARY=""
REVIEWED_HEAD=""
DRY_RUN=false
BODY_ONLY=false
BLOCKING_ONLY=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --pr) PR="${2:?--pr requires a value}"; shift 2 ;;
    --head) REVIEWED_HEAD="${2:?--head requires a value}"; shift 2 ;;
    --findings) FINDINGS="${2:?--findings requires a value}"; shift 2 ;;
    --summary) SUMMARY="${2:?--summary requires a value}"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    --body-only) BODY_ONLY=true; shift ;;
    --blocking-only) BLOCKING_ONLY=true; shift ;;
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

# ── Validate every finding before any network call ───────────────────
STATUS_RE='^(confirmed|accepted|already raised|dismissed|fixed|dropped)( .*)?$'
VERDICT_RE='^(confirms|contradicts|not fixed)$'
BLOCKING_RE='[(, ]blocking[),]'
for ((i = 0; i < N; i++)); do
  msg=$(field "$i" message)
  [ -n "$msg" ] || { echo "error: finding $i has no message" >&2; exit 2; }
  check_conventional_label "$msg" || { echo "error: finding $i refused, nothing posted" >&2; exit 2; }
  line=$(field "$i" line)
  if [ -n "$line" ] && ! [[ "$line" =~ ^[0-9]+$ ]]; then
    echo "error: finding $i has a non-integer line: $line" >&2; exit 2
  fi
  status=$(field "$i" status)
  if [ -n "$status" ] && ! [[ "$status" =~ $STATUS_RE ]]; then
    echo "error: finding $i has status '$status'; use confirmed, accepted, already raised, dismissed, fixed or dropped" >&2; exit 2
  fi
  dup_id=$(field "$i" dup.id); dup_verdict=$(field "$i" dup.verdict)
  if [ -n "$dup_id$dup_verdict" ]; then
    [[ "$dup_id" =~ ^[0-9]+$ ]] || { echo "error: finding $i has a dup without an integer id" >&2; exit 2; }
    [[ "$dup_verdict" =~ $VERDICT_RE ]] || { echo "error: finding $i has dup verdict '$dup_verdict'; use confirms, contradicts or not fixed" >&2; exit 2; }
  fi
  if [[ "$status" == "already raised"* ]] && [ -z "$dup_id" ]; then
    echo "error: finding $i is already raised but names no dup thread" >&2; exit 2
  fi
done

# ── Select what posts ────────────────────────────────────────────────
# One disposition per finding: `thread` (a new thread, or the body), `reply` (into the dup
# thread), `confirms` (agreement, never a comment), `status` (not postable), `blocking`
# (held back by --blocking-only).
DISP=()
POSTABLE=0
NEED_REVIEW=false   # a pending review: a new thread outside --body-only, or any reply
for ((i = 0; i < N; i++)); do
  status=$(field "$i" status); dup_verdict=$(field "$i" dup.verdict)
  first=$(field "$i" message | head -1)
  d=thread
  case "$status" in dismissed*|fixed*|dropped*) d=status ;; esac
  if [ "$d" = thread ] && [ -n "$dup_verdict" ]; then
    case "$dup_verdict" in confirms) d=confirms ;; *) d=reply ;; esac
  fi
  if [ "$BLOCKING_ONLY" = true ] && [ "$d" != status ] && [ "$d" != confirms ] && ! [[ "$first" =~ $BLOCKING_RE ]]; then
    d=blocking
  fi
  DISP[i]=$d
  case "$d" in
    thread) POSTABLE=$((POSTABLE + 1)); [ "$BODY_ONLY" = true ] || NEED_REVIEW=true ;;
    reply) POSTABLE=$((POSTABLE + 1)); NEED_REVIEW=true ;;
  esac
done
if [ "$N" -gt 0 ] && [ "$POSTABLE" -eq 0 ]; then
  echo "error: nothing to post — every finding is a confirms, a non-blocking or a non-postable status; nothing posted" >&2
  exit 2
fi

# ── Resolve the PR and its own repo ──────────────────────────────────
PR_ARGS=()
[ -n "$PR" ] && PR_ARGS+=("$PR")
PR_JSON=$(gh pr view ${PR_ARGS[@]+"${PR_ARGS[@]}"} --json id,number,headRefOid,url 2>/dev/null) || {
  echo "error: failed to resolve the PR — pass --pr <number-or-url>, or check gh authentication" >&2
  echo "hint: a --pr URL selects the repository; a number uses the repository of the current directory" >&2
  exit 1
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

# ── Every line anchor sits in a hunk of the PR diff ──────────────────
# GitHub takes a line thread only on a line of a diff hunk. On any other line, the thread
# moves to the file, and the author reads an anchor that the review did not mean
# (flow-components #10597).
if [ "$BODY_ONLY" != true ]; then
  HUNKS=$(gh api "repos/$REPO_SLUG/pulls/$PR_NUMBER/files" --paginate --jq '
    .[] | .filename as $f
    | if .patch == null then "\($f)\t-\t-"
      else .patch | [scan("@@ -[0-9]+(?:,[0-9]+)? \\+([0-9]+)(?:,([0-9]+))? @@")][] | "\($f)\t\(.[0])\t\(.[1] // "1")"
      end' 2>/dev/null) || HUNKS=""
  if [ -z "$HUNKS" ]; then
    echo "warn: could not read the diff hunks of the PR, so the line anchors are not checked" >&2
  else
    OUTSIDE=""
    for ((i = 0; i < N; i++)); do
      [ "${DISP[i]}" = thread ] || continue
      [ "$(field "$i" summary_only)" = true ] && continue
      file=$(field "$i" file); line=$(field "$i" line)
      [ -n "$file" ] && [ -n "$line" ] || continue
      where_in=$(printf '%s\n' "$HUNKS" | awk -F'\t' -v p="$file" -v l="$line" '
        $1 == p {
          seen = 1
          if ($2 == "-") { ok = 1; exit }
          if ($3 > 0 && l >= $2 && l < $2 + $3) { ok = 1; exit }
          if ($3 > 0) r = r (r == "" ? "" : ", ") $2 "-" ($2 + $3 - 1)
        }
        END { if (ok) print "ok"; else if (!seen) print "in no file of the diff"; else print "outside the hunks (" r ")" }')
      [ "$where_in" = ok ] || OUTSIDE="$OUTSIDE  finding $i: $file:$line is $where_in
"
    done
    if [ -n "$OUTSIDE" ]; then
      echo "error: GitHub would move these line anchors to the file:" >&2
      printf '%s' "$OUTSIDE" >&2
      echo "re-anchor each one on a line of a hunk, or set \"summary_only\": true (pipeline.md §5.6); nothing posted" >&2
      exit 2
    fi
  fi
fi

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
M_REPLY='mutation($reviewId:ID!,$threadId:ID!,$body:String!){addPullRequestReviewThreadReply(input:{pullRequestReviewId:$reviewId,pullRequestReviewThreadId:$threadId,body:$body}){comment{url}}}'
Q_THREADS='query($owner:String!,$name:String!,$number:Int!,$endCursor:String){repository(owner:$owner,name:$name){pullRequest(number:$number){reviewThreads(first:100,after:$endCursor){pageInfo{hasNextPage endCursor} nodes{id comments(first:100){nodes{databaseId}}}}}}}'

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

# A reply goes into the thread that holds the comment with that REST id. The thread node
# ids come from one query, fetched on the first reply. Sets THREAD_URL to the reply URL.
THREAD_IDS=""
add_reply() {  # add_reply <comment id> <body>
  local node
  if [ -z "$THREAD_IDS" ]; then
    THREAD_IDS=$(gh api graphql --paginate -f query="$Q_THREADS" -f owner="${REPO_SLUG%%/*}" -f name="${REPO_SLUG##*/}" -F number="$PR_NUMBER" \
      --jq '.data.repository.pullRequest.reviewThreads.nodes[] | .id as $t | .comments.nodes[] | "\(.databaseId) \($t)"' 2>/dev/null || true)
    [ -n "$THREAD_IDS" ] || THREAD_IDS="-"
  fi
  node=$(printf '%s\n' "$THREAD_IDS" | awk -v id="$1" '$1 == id { print $2; exit }')
  [ -n "$node" ] || return 1
  THREAD_URL=$(gh api graphql -f query="$M_REPLY" -f reviewId="$REVIEW_ID" -f threadId="$node" -f body="$2" \
    --jq '.data.addPullRequestReviewThreadReply.comment.url // empty' 2>/dev/null || true)
  [ -n "$THREAD_URL" ]
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

if [ "$DRY_RUN" != true ] && [ "$NEED_REVIEW" = true ]; then
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
LISTED=0
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
  status=$(field "$i" status)
  dup_id=$(field "$i" dup.id)
  first="${msg%%$'\n'*}"
  label=$(printf '%s' "$first" | sed -n 's/^\*\*\([^*]*\):\*\* .*/\1/p')
  where="${file:-}${line:+:$line}"
  [ -n "$where" ] || where="(no anchor)"

  case "${DISP[i]}" in
    confirms) echo "confirms: $where (thread $dup_id, agreement is not a comment)"; LISTED=$((LISTED + 1)); continue ;;
    status) echo "skipped: $where (status $status)"; LISTED=$((LISTED + 1)); continue ;;
    blocking) echo "skipped: $where (not blocking)"; LISTED=$((LISTED + 1)); continue ;;
  esac

  if [ "${DISP[i]}" = thread ] && [ "$BODY_ONLY" != true ] && [ -n "$file" ] && [ -n "$line" ] && [ "$allow" != true ]; then
    near=$(nearby "$file" "$line")
    if [ -n "$near" ]; then
      echo "skipped: $where (existing thread ${near% } — triage it first: verify its claim, then set dup on the finding, pipeline.md §5.2)"
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
  if [ "${DISP[i]}" = reply ]; then
    if [ "$DRY_RUN" = true ]; then
      printf -- '--- reply to thread %s (%s) ---\n%s\n\n' "$dup_id" "$where" "$thread_body"
      INLINE=$((INLINE + 1))
      continue
    fi
    if add_reply "$dup_id" "$thread_body"; then
      echo "reply: $where (thread $dup_id) $THREAD_URL"; INLINE=$((INLINE + 1)); continue
    fi
    echo "body: $where (the reply into thread $dup_id failed)"
    BODY_N=$((BODY_N + 1))
    UNANCHORED="$UNANCHORED

**re thread $dup_id${file:+, \`$where\`}**

$msg"
    continue
  fi
  if [ "$BODY_ONLY" = true ] || [ "$(field "$i" summary_only)" = true ]; then
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
  if [ "$BODY_ONLY" = true ]; then echo "body: $where (--body-only)"; else echo "body: $where"; fi
  BODY_N=$((BODY_N + 1))
  loc=""
  [ "$where" != "(no anchor)" ] && loc="**\`$where\`**

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
    OVERVIEW="$OVERVIEW One of them is below, in this body."
  elif [ "$BODY_N" -gt 1 ]; then
    OVERVIEW="$OVERVIEW $BODY_N of them are below, in this body."
  fi
fi
BODY="$PREFIX

$OVERVIEW"
[ -n "$SUMMARY" ] && BODY="$BODY

$(cat "$SUMMARY")"
[ -n "$UNANCHORED" ] && BODY="$BODY$UNANCHORED"

if [ "$DRY_RUN" = true ]; then
  printf -- '--- review body ---\n%s\n' "$BODY"
  echo "dry run: $POSTED findings, $SKIPPED skipped, $LISTED listed, nothing posted"
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
echo "posted: $INLINE threads and replies, $BODY_N in the body, $SKIPPED skipped, $LISTED listed"
echo "review: $URL"
