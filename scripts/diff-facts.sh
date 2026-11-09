#!/usr/bin/env bash
# diff-facts.sh — the facts of a diff that git alone can answer, for the passes. The core
# prints the moved or reindented share of the diff and the new test files. Each fact pack in
# scripts/facts/ adds the facts of one kind of repository.
#
# Usage:
#   diff-facts.sh --base <sha> --head <sha>
#
# Run it from inside the target repository. review-plan.sh calls it in both modes and
# quotes the lines under Settled facts. pr-screen.sh takes `reach_max` for its verdict.
#
# A fact pack is an executable scripts/facts/<name>.sh. The core runs every pack from the
# repository root with --base <sha> --head <sha>, and exports the lanes as FACTS_PROD and
# FACTS_TESTS (one path per line). A pack that does not apply to the repository prints
# nothing. Otherwise it prints `<key>: <value>` lines. A `rule: <sentence>` line tells the
# passes how to judge the fact lines above it. A pack may print `reach_max: <n>`, the most
# other packages that import one changed module. The default is 0.
#
# Exit codes: 0 ok · 1 git could not answer · 2 usage error.
set -euo pipefail

BASE=""; HEAD=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --base) BASE="${2:?--base requires a value}"; shift 2 ;;
    --head) HEAD="${2:?--head requires a value}"; shift 2 ;;
    --help|-h) sed -n '2,/^set -euo pipefail$/{/^set /d;p;}' "$0"; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done
[[ "$BASE" =~ ^[0-9a-f]{7,40}$ ]] || { echo "error: --base takes a commit SHA" >&2; exit 2; }
[[ "$HEAD" =~ ^[0-9a-f]{7,40}$ ]] || { echo "error: --head takes a commit SHA" >&2; exit 2; }

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "error: not a git repository" >&2; exit 1; }
cd "$REPO_ROOT"

# ── Lanes ─────────────────────────────────────────────────────────────
# The lanes of lib/lanes.sh, so both scripts split the lanes alike. One path per line.
git diff --name-only --no-renames "$BASE..$HEAD" >/dev/null 2>&1 || { echo "error: git cannot diff $BASE..$HEAD" >&2; exit 1; }
# shellcheck source=lib/lanes.sh
. "$SCRIPT_DIR/lib/lanes.sh"
lanes_split
# shellcheck disable=SC2086
PROD=$(printf '%s\n' $PROD_FILES | sed '/^$/d')
# shellcheck disable=SC2086
TESTS=$(printf '%s\n' $TEST_FILES | sed '/^$/d')

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

# New test files, with their size next to the production size. A new suite for a small fix
# breaks the "no new test file unless necessary" rule of the tests pass (#12974: 52 lines of
# a new suite for a 5-line fix).
NEW_TESTS=""
PROD_LINES=$(git diff --numstat "$BASE..$HEAD" -- $PROD 2>/dev/null | awk '$1 != "-" { n += $1 + $2 } END { print n + 0 }')
for f in $(git diff --name-only --diff-filter=A "$BASE..$HEAD" -- $TESTS 2>/dev/null | grep -v '__snapshots__' | grep -v '/screenshots/' || true); do
  n=$(git show "$HEAD:$f" 2>/dev/null | wc -l | tr -d ' ')
  NEW_TESTS="${NEW_TESTS:+$NEW_TESTS, }$f ($n lines)"
done

# ── Fact packs ────────────────────────────────────────────────────────
PACKS=""
export FACTS_PROD="$PROD" FACTS_TESTS="$TESTS"
for pack in "$SCRIPT_DIR"/facts/*.sh; do
  [ -x "$pack" ] || continue
  out=$("$pack" --base "$BASE" --head "$HEAD" 2>&1) \
    || out="error: $(basename "$pack") failed — $(printf '%s' "$out" | tail -1)"
  [ -n "$out" ] && PACKS="${PACKS}${out}
"
done

# ── Print ─────────────────────────────────────────────────────────────
echo "=== DIFF_FACTS ==="
echo "diff_noise: $NOISE_N of $NOISE_TOTAL changed production lines are moved or reindented (the same text on both sides)"
echo "new_test_files: ${NEW_TESTS:-none}${NEW_TESTS:+ for $PROD_LINES changed production lines}"
printf '%s' "$PACKS"
