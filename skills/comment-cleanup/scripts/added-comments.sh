#!/usr/bin/env bash
# added-comments.sh — list the comment blocks that a diff ADDS.
#
# Usage:
#   added-comments.sh [--diff | --commit <sha> | --staged | --working] [path ...]
#
# --diff     (default) the merge base of the base branch to HEAD
# --commit   one commit, against its first parent
# --staged   the index against HEAD
# --working  the working tree against the index
#
# Output, one line per contiguous comment block:
#   <file>:<line> | <text>
# `<line>` is the post-change line number of the first line of the block. `<text>` is the
# block joined with ` / `. A block that holds a lint or a type directive is omitted, and so
# is a license header at the top of a file.
#
# Exit codes: 0 with output, 0 with no output when the diff adds no comment, 1 on a guard.

set -euo pipefail

MODE=diff
COMMIT=""
PATHS=()

while [ $# -gt 0 ]; do
  case "$1" in
    --diff) MODE=diff ;;
    --staged) MODE=staged ;;
    --working) MODE=working ;;
    --commit) MODE=commit; COMMIT="${2:-}"; shift ;;
    --help|-h) sed -n '2,20p' "$0"; exit 0 ;;
    --*) echo "unknown flag: $1" >&2; exit 1 ;;
    *) PATHS+=("$1") ;;
  esac
  shift
done

git rev-parse --git-dir >/dev/null 2>&1 || { echo "refuse: not a git repository" >&2; exit 1; }

DIFF_ARGS=()
case "$MODE" in
  staged) DIFF_ARGS=(--cached) ;;
  working) DIFF_ARGS=() ;;
  commit)
    [ -n "$COMMIT" ] || { echo "refuse: --commit needs a sha" >&2; exit 1; }
    git rev-parse --verify "$COMMIT^{commit}" >/dev/null 2>&1 ||
      { echo "refuse: cannot resolve $COMMIT" >&2; exit 1; }
    DIFF_ARGS=("$COMMIT^!")
    ;;
  diff)
    BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
    case "$BRANCH" in
      main|master) echo "refuse: on $BRANCH — run this on a topic branch" >&2; exit 1 ;;
      maintenance/*) echo "refuse: on a maintenance branch — run this on a topic branch" >&2; exit 1 ;;
      HEAD|"") echo "refuse: detached HEAD — check out the branch first" >&2; exit 1 ;;
    esac
    if git rev-parse --verify origin/main >/dev/null 2>&1; then BASE_BRANCH=main
    elif git rev-parse --verify origin/master >/dev/null 2>&1; then BASE_BRANCH=master
    else echo "refuse: cannot find origin/main or origin/master" >&2; exit 1; fi
    BASE=$(git merge-base "origin/$BASE_BRANCH" HEAD 2>/dev/null || echo "")
    [ -n "$BASE" ] || { echo "refuse: cannot resolve the merge base — fetch $BASE_BRANCH" >&2; exit 1; }
    DIFF_ARGS=("$BASE..HEAD")
    ;;
esac

git diff -U0 ${DIFF_ARGS[@]+"${DIFF_ARGS[@]}"} ${PATHS[@]+-- "${PATHS[@]}"} | awk '
  function flush() {
    if (n == 0) return
    if (!skip && !(start <= 3 && license)) printf "%s:%d | %s\n", file, start, text
    n = 0; skip = 0; license = 0; text = ""; in_block = 0
  }
  /^\+\+\+ / { flush(); file = ($0 ~ /^\+\+\+ b\//) ? substr($0, 7) : ""; next }
  /^--- / || /^diff --git / || /^index / || /^(new|deleted) file/ || /^similarity / || /^rename / { next }
  /^@@ / {
    flush()
    # @@ -a,b +c,d @@ — c is the first post-change line of the hunk
    split($3, h, ",")
    lineno = h[1] + 0
    next
  }
  /^\+/ {
    if (file == "") next
    body = substr($0, 2)
    bare = body
    sub(/^[ \t]+/, "", bare)
    is_comment = in_block || (bare ~ /^\/\// || bare ~ /^\/\*/ || bare ~ /^\*/ || bare ~ /^<!--/)
    if (is_comment) {
      was_open = in_block
      if (n > 0 && lineno == prev + 1) {
        text = text " / " bare
      } else {
        was_open = 0
        flush()
        start = lineno
        text = bare
      }
      if (was_open) { in_block = (bare ~ /\*\// || bare ~ /-->/) ? 0 : 1 }
      else { in_block = ((bare ~ /^\/\*/ || bare ~ /^<!--/) && !(bare ~ /\*\// || bare ~ /-->/)) ? 1 : 0 }
      n++
      prev = lineno
      if (bare ~ /eslint-disable/ || bare ~ /prettier-ignore/ || bare ~ /@ts-(expect-error|ignore|nocheck)/ ||
          bare ~ /c8 ignore/ || bare ~ /istanbul ignore/ || bare ~ /webpack|vite-ignore/) skip = 1
      if (bare ~ /@license/ || bare ~ /Copyright/) license = 1
    } else {
      in_block = 0
      flush()
    }
    lineno++
    next
  }
  { next }
  END { flush() }
' || true
