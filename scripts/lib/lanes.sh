# lanes.sh: sourced by review-plan.sh and diff-facts.sh. The test and code patterns, the
# file lanes of a diff, the files with a comment beside a hunk, and the commits of the branch.
#
# Reads: BASE, HEAD
# Sets: TEST_RE, CODE_RE, CHANGED, BINARY_FILES, TEST_FILES, PROD_FILES, COMMENT_FILES,
#       BRANCH_COMMITS
#
# The lists of files hold one path per word, each followed by a space.

# The prepared diff is split so a pass reads only its own material: the test diff
# is most of a branch's line count, and every pass that does not review tests was
# paying for it. See references/profiles.md's `reads` column.
TEST_RE='(^|/)(test|tests|__tests__|it)/|\.(test|spec)\.[cm]?[jt]sx?$|Test\.java$|IT\.java$|Tests?\.kt$'
# A file that a test can cover. The plan drops the tests pass when the diff has none.
CODE_RE='\.([cm]?[jt]sx?|java|kt|css|scss|html|py|sh)$'

lanes_split() {  # lanes_split — CHANGED, BINARY_FILES, TEST_FILES and PROD_FILES of BASE..HEAD
  CHANGED=""
  TEST_FILES=""
  PROD_FILES=""
  BINARY_FILES=""
  if [ -n "$BASE" ]; then
    CHANGED=$(git diff --name-only --no-renames "$BASE..$HEAD" 2>/dev/null || echo "")
  fi
  if [ -n "$CHANGED" ]; then
    # Binaries get their own lane: named, not diffed (a patch would only hold a
    # `Bin N -> M bytes` stub), and never dropped — screenshot baselines are evidence.
    BINARY_FILES=$(git diff --numstat "$BASE..$HEAD" 2>/dev/null | awk -F'\t' '$1 == "-" && $2 == "-" { print $3 }' | tr '\n' ' ' || true)
    local text_changed="$CHANGED" bin
    if [ -n "$BINARY_FILES" ]; then
      for bin in $BINARY_FILES; do
        text_changed=$(printf '%s\n' "$text_changed" | grep -vxF "$bin" || true)
      done
    fi
    TEST_FILES=$(printf '%s\n' "$text_changed" | grep -E "$TEST_RE" | tr '\n' ' ' || true)
    PROD_FILES=$(printf '%s\n' "$text_changed" | grep -vE "$TEST_RE" | tr '\n' ' ' || true)
  fi
  return 0
}

plan_lanes() {
  lanes_split

  # Files with a comment inside or beside a hunk — the code pass's extra input for
  # its Comments category, which has two questions: comments the diff ADDS (policy)
  # and comments the diff left stale (rot). The first needs added comment lines; the
  # second needs comments near changed code, so the window is -U3 and removed/context
  # lines count too. A file with no comment within three lines of a change cannot
  # hold either finding.
  COMMENT_FILES=""
  if [ -n "$BASE" ]; then
    COMMENT_FILES=$(git diff -U3 "$BASE..$HEAD" 2>/dev/null | awk '
      /^diff --git |^index |^--- |^\+\+\+ |^@@ |^(new|deleted) file|^similarity|^rename / {
        if ($0 ~ /^\+\+\+ b\//) { file = substr($0, 7) }
        next
      }
      file == "" { next }
      {
        body = substr($0, 2)
        if (body ~ /(\/\/|\/\*|\*\/|<!--)/ || body ~ /^[ \t]*\*[ \t]/) {
          if (!(file in seen)) { seen[file] = 1; printf "%s ", file }
        }
      }
    ' || true)
  fi

  # The branch's own commit sequence. `base..head` flattens it, but the ORDER is
  # evidence: a fix commit landing after the commit that captured a baseline, or
  # after the test that was supposed to pin it, is exactly the stale-baseline and
  # untested-fix smell — and it is invisible in the squashed diff.
  BRANCH_COMMITS=""
  if [ -n "$BASE" ]; then
    BRANCH_COMMITS=$(git log --oneline --no-decorate --reverse "$BASE..$HEAD" 2>/dev/null || true)
  fi
  return 0
}
