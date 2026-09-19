#!/usr/bin/env bash
# list-comments.sh — list comment blocks, either the ones a diff ADDED or every one in a file.
#
# Usage:
#   list-comments.sh [--diff | --commit <sha> | --staged | --working] [path ...]
#   list-comments.sh --all <path ...>
#   list-comments.sh --package <name>
#
# Diff modes, which list only the comments that the change ADDED:
#   --diff     (default) the merge base of the base branch to HEAD
#   --commit   one commit, against its first parent
#   --staged   the index against HEAD
#   --working  the working tree against the index
#   A path narrows any diff mode to that file or directory.
#
# Whole-source modes, which list EVERY comment in the files that they reach:
#   --all      the files and the directories that follow
#   --package  one package: packages/<name>/src, else packages/<name>, else <name>
#   Both walk source files only (js, mjs, cjs, jsx, ts, tsx, css, html) and skip
#   node_modules, dist, build, test directories and `.d.ts` files.
#
# Output, one line per contiguous comment block:
#   <file>:<line> | <kind> | <text>
# `<line>` is the line number of the first line of the block. `<kind>` is `docblock` for a
# `/** */` block, `html` for a `<!-- -->` block, else `inline`. `<text>` is the block joined
# with ` / `. A block that holds a lint or a type directive is omitted, and so is a license
# header at the top of a file, and so is a docblock that holds only tags.
#
# Exit codes: 0 with output, 0 with no output when nothing matches, 1 on a guard.

set -euo pipefail

MODE=diff
COMMIT=""
PACKAGE=""
PATHS=()

while [ $# -gt 0 ]; do
  case "$1" in
    --diff) MODE=diff ;;
    --staged) MODE=staged ;;
    --working) MODE=working ;;
    --all) MODE=all ;;
    --commit) MODE=commit; COMMIT="${2:-}"; shift ;;
    --package) MODE=package; PACKAGE="${2:-}"; shift ;;
    --help|-h) sed -n '2,30p' "$0"; exit 0 ;;
    --*) echo "unknown flag: $1" >&2; exit 1 ;;
    *) PATHS+=("$1") ;;
  esac
  shift
done

git rev-parse --git-dir >/dev/null 2>&1 || { echo "refuse: not a git repository" >&2; exit 1; }

# One parser for both kinds of input. A whole-source mode synthesizes a diff-shaped stream,
# so the block grouping, the directive filter and the line numbers stay in one place.
parse() {
  awk '
    function flush() {
      if (n == 0) return
      if (!skip && !(start <= 3 && license) && !(kind == "docblock" && !prose))
        printf "%s:%d | %s | %s\n", file, start, kind, text
      n = 0; skip = 0; license = 0; text = ""; in_block = 0; prose = 0; kind = ""
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
          # A diff hunk can start inside a docblock, on a ` * ` line. Only a block comment has one.
          kind = (bare ~ /^\/\*\*/ || bare ~ /^\*/) ? "docblock" : (bare ~ /^<!--/) ? "html" : "inline"
        }
        # A docblock line is prose unless it is empty or starts with a tag.
        content = bare
        sub(/^(\/\*\*|\/\*|\*\/|\*|\/\/)[ \t]*/, "", content)
        sub(/[ \t]*\*\/[ \t]*$/, "", content)
        if (content != "" && content !~ /^@/) prose = 1
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
  '
}

# ── Whole-source modes ────────────────────────────────────────────────
if [ "$MODE" = all ] || [ "$MODE" = package ]; then
  if [ -n "$(git status --porcelain --untracked-files=no 2>/dev/null)" ]; then
    echo "refuse: tracked files are dirty — commit or stash first, so that a bad edit reverts" >&2
    exit 1
  fi
  ROOTS=()
  if [ "$MODE" = package ]; then
    [ -n "$PACKAGE" ] || { echo "refuse: --package needs a name" >&2; exit 1; }
    for c in "packages/$PACKAGE/src" "packages/$PACKAGE" "$PACKAGE"; do
      if [ -d "$c" ]; then ROOTS=("$c"); break; fi
    done
    [ ${#ROOTS[@]} -gt 0 ] || { echo "refuse: no directory for package $PACKAGE" >&2; exit 1; }
  else
    [ ${#PATHS[@]} -gt 0 ] || { echo "refuse: --all needs at least one path" >&2; exit 1; }
    ROOTS=("${PATHS[@]}")
    for r in "${ROOTS[@]}"; do
      [ -e "$r" ] || { echo "refuse: no such path: $r" >&2; exit 1; }
    done
  fi

  # git ls-files keeps the walk to tracked sources and honors .gitignore for free.
  FILES=$(git ls-files -- "${ROOTS[@]}" | awk '
    /\.d\.ts$/ { next }
    /(^|\/)(node_modules|dist|build|coverage)\// { next }
    /(^|\/)tests?\// { next }
    /\.(js|mjs|cjs|jsx|ts|tsx|css|html)$/ { print }
  ')
  [ -n "$FILES" ] || exit 0

  # Synthesize the diff shape that the parser reads: every line of every file is "added".
  printf '%s\n' "$FILES" | while IFS= read -r f; do
    [ -f "$f" ] || continue
    printf '+++ b/%s\n' "$f"
    printf '@@ -0,0 +1,%s @@\n' "$(wc -l < "$f" | tr -d ' ')"
    sed 's/^/+/' "$f"
  done | parse
  exit 0
fi

# ── Diff modes ────────────────────────────────────────────────────────
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
      main|master) echo "refuse: on $BRANCH — a diff run needs a topic branch, or pass --all <path>" >&2; exit 1 ;;
      maintenance/*) echo "refuse: on a maintenance branch — pass --all <path> instead" >&2; exit 1 ;;
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

git diff -U0 ${DIFF_ARGS[@]+"${DIFF_ARGS[@]}"} ${PATHS[@]+-- "${PATHS[@]}"} | parse
