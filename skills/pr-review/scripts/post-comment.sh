#!/usr/bin/env bash
# post-comment.sh — Post a review comment on a GitHub PR.
#
# Requires the `gh` CLI, authenticated for the current repo. Fails loudly without it.
#
# Usage:
#   post-comment.sh [--pr <number-or-url>] --message <text>                    # general comment
#   post-comment.sh [--pr <number-or-url>] --file <path> --line <N[:M]> --message <text>  # new side
#   post-comment.sh [--pr <number-or-url>] --file <path> --old-line <N> --message <text>  # old side
#   post-comment.sh [--pr <number-or-url>] --reply <comment-id> --message <text>  # reply in a diff thread
#
# The target repo is derived from the PR itself (so a PR URL from another repo
# posts to THAT repo, never to the cwd's repo by accident).
#
# Positioned comments must target a line that appears in the PR diff; when the
# GitHub API rejects the position (422), the comment is posted as a general
# comment prefixed with the intended location, and "posted: general_fallback"
# is printed. Any other API error aborts — a failed post beats a wrong post.
#
# The :robot: AI-generated prefix is prepended automatically.
set -euo pipefail

PR=""
FILE=""
LINE=""
OLD_LINE=""
REPLY_ID=""
MESSAGE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --pr) PR="${2:?--pr requires a value}"; shift 2 ;;
    --file) FILE="${2:?--file requires a value}"; shift 2 ;;
    --line) LINE="${2:?--line requires a value}"; shift 2 ;;
    --old-line) OLD_LINE="${2:?--old-line requires a value}"; shift 2 ;;
    --reply) REPLY_ID="${2:?--reply requires a value}"; shift 2 ;;
    --message) MESSAGE="${2:?--message requires a value}"; shift 2 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

if [ -z "$MESSAGE" ]; then
  echo "error: --message is required" >&2
  exit 1
fi

if ! command -v gh >/dev/null 2>&1; then
  echo "error: gh CLI not found — this skill requires it" >&2
  exit 1
fi

# Prepend the AI-generated prefix
FULL_MESSAGE=":robot: AI-generated

$MESSAGE"

# ── Validate flag combinations ────────────────────────────────────────
if [ -n "$LINE" ] && [ -n "$OLD_LINE" ]; then
  echo "error: --line and --old-line cannot be used together" >&2
  exit 1
fi

if { [ -n "$LINE" ] || [ -n "$OLD_LINE" ]; } && [ -z "$FILE" ]; then
  echo "error: --line/--old-line require --file" >&2
  exit 1
fi

if [ -n "$REPLY_ID" ] && [ -n "$FILE" ]; then
  echo "error: --reply and --file are mutually exclusive" >&2
  exit 1
fi

# ── Resolve PR number, head SHA, and the PR's own repo ────────────────
PR_ARGS=()
if [ -n "$PR" ]; then
  PR_ARGS+=("$PR")
fi

PR_JSON=$(gh pr view ${PR_ARGS[@]+"${PR_ARGS[@]}"} --json number,headRefOid,url 2>/dev/null) || {
  echo "error: failed to resolve the PR" >&2
  echo "hint: pass --pr <number-or-url>, or check gh authentication" >&2
  exit 1
}
PR_NUMBER=$(echo "$PR_JSON" | grep -o '"number":[0-9]*' | head -1 | cut -d: -f2 || true)
HEAD_SHA=$(echo "$PR_JSON" | grep -o '"headRefOid":"[^"]*"' | head -1 | cut -d'"' -f4 || true)
PR_URL=$(echo "$PR_JSON" | grep -o '"url":"[^"]*"' | head -1 | cut -d'"' -f4 || true)

# https://github.com/OWNER/REPO/pull/N → OWNER/REPO — pin every call to the
# PR's own repo so a URL from another repo never posts into the cwd's repo.
REPO_SLUG=$(echo "$PR_URL" | sed -n 's|^https://[^/]*/\([^/]*/[^/]*\)/pull/.*|\1|p')
if [ -z "$REPO_SLUG" ] || [ -z "$PR_NUMBER" ] || [ -z "$HEAD_SHA" ]; then
  echo "error: could not derive repo/number/head from the PR (got url='$PR_URL')" >&2
  exit 1
fi

BODY_FILE=$(mktemp)
trap 'rm -f "$BODY_FILE"' EXIT
printf '%s' "$FULL_MESSAGE" > "$BODY_FILE"

post_general() {
  gh pr comment "$PR_NUMBER" --repo "$REPO_SLUG" --body-file "$BODY_FILE" >/dev/null
}

if [ -n "$REPLY_ID" ]; then
  # ── Reply to an existing review-comment thread ──────────────────────
  gh api "repos/$REPO_SLUG/pulls/$PR_NUMBER/comments/$REPLY_ID/replies" \
    --method POST -F "body=@$BODY_FILE" >/dev/null
  echo "posted: true (reply to $REPLY_ID)"
elif [ -n "$FILE" ]; then
  # ── Positioned diff comment ──────────────────────────────────────────
  API_ARGS=(
    --method POST
    -F "body=@$BODY_FILE"
    -f "commit_id=$HEAD_SHA"
    -f "path=$FILE"
  )
  if [ -n "$OLD_LINE" ]; then
    API_ARGS+=(-F "line=$OLD_LINE" -f "side=LEFT")
    TARGET_DESC="$FILE:$OLD_LINE (old side)"
  elif [[ "$LINE" == *:* ]]; then
    START_LINE="${LINE%%:*}"
    END_LINE="${LINE##*:}"
    API_ARGS+=(-F "start_line=$START_LINE" -f "start_side=RIGHT" -F "line=$END_LINE" -f "side=RIGHT")
    TARGET_DESC="$FILE:$START_LINE-$END_LINE"
  else
    API_ARGS+=(-F "line=$LINE" -f "side=RIGHT")
    TARGET_DESC="$FILE:$LINE"
  fi

  if API_ERR=$(gh api "repos/$REPO_SLUG/pulls/$PR_NUMBER/comments" "${API_ARGS[@]}" 2>&1 >/dev/null); then
    echo "posted: true ($TARGET_DESC)"
  elif echo "$API_ERR" | grep -qi 'HTTP 422'; then
    # Position rejected (line not part of the PR diff) — post as a labelled
    # general comment instead so the finding is not lost.
    printf '%s\n\n%s' ":robot: AI-generated — re **$TARGET_DESC** (position rejected, posted as general comment)" "$MESSAGE" > "$BODY_FILE"
    post_general
    echo "posted: general_fallback ($TARGET_DESC)"
    echo "warn: positioned comment rejected (HTTP 422): $API_ERR" >&2
  else
    echo "error: failed to post positioned comment ($TARGET_DESC): $API_ERR" >&2
    exit 1
  fi
else
  # ── General comment ──────────────────────────────────────────────────
  post_general
  echo "posted: true (general)"
fi
