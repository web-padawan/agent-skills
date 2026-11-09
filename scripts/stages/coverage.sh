#!/usr/bin/env bash
# coverage.sh: the stage script of the `coverage` stage. The coverage check of self-review
# mutates source lines of the diff, one at a time, and runs the tests. A mutant that the
# tests do not catch is a coverage gap.
#
# Usage:
#   coverage.sh --base <sha> --head <sha> --budget <n>
#
# review-plan.sh runs it from the repository root, per the stage contract of
# docs/contracts.md. It prints `mutants: <budget>`. When the budget is above 0, it also
# prints `mutant_pool:`, the count of added source lines that a mutant can change.
# Steps: skills/self-review/references/mutation.md.
#
# Exit codes: 0 ok, 2 usage error.
set -euo pipefail

BASE=""; HEAD=""; BUDGET=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --base) BASE="${2:?--base requires a value}"; shift 2 ;;
    --head) HEAD="${2:?--head requires a value}"; shift 2 ;;
    --budget) BUDGET="${2:?--budget requires a value}"; shift 2 ;;
    --help|-h) sed -n '2,/^set -euo pipefail$/{/^set /d;p;}' "$0"; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done
[[ "$BUDGET" =~ ^[0-9]+$ ]] || { echo "error: --budget takes a number" >&2; exit 2; }
FACTS_PROD=${FACTS_PROD:-}

# Mutant candidate pool — advisory, not a budget: non-styling source lines the
# coverage stage could mutate (mutation.md skips styling), so a styling-only diff
# reports 0 instead of sending the stage looking for work that does not exist.
MUTANT_POOL=0
if [ "$BUDGET" -gt 0 ] && [ -n "$FACTS_PROD" ] && [ -n "$BASE" ]; then
  # shellcheck disable=SC2086
  MUTANT_POOL=$(git diff --unified=0 "$BASE..$HEAD" -- $FACTS_PROD 2>/dev/null | awk '
    /^\+\+\+ b\// { file = substr($0, 7); next }
    /^\+/ {
      if (file !~ /\.[cm]?[jt]sx?$/) next          # source code only
      if (file ~ /(^|\/)styles\// || file ~ /-styles\.[cm]?[jt]s$/) next   # styling by construction
      body = substr($0, 2)
      sub(/^[ \t]+/, "", body)
      if (body == "") next
      if (body ~ /^(import|export[ \t]+\{|export[ \t]+\*)/) next
      if (body ~ /^(\/\/|\/\*|\*|\*\/)/) next
      if (body ~ /^[)}\]`;,]+$/) next
      if (body ~ /^-{0,2}[_a-z][-_a-z0-9]*:[ \t]/) next   # CSS declaration, custom properties included
      if (body ~ /^[.:&#@[$]/ || body ~ /^[a-z-]+[ \t]*\{$/) next   # CSS selector, at-rule, interpolated selector
      if (body ~ /^(var|color-mix|calc|light-dark|oklch|linear-gradient)\(/) next   # wrapped CSS value
      n++
    }
    END { print n + 0 }' || echo 0)
fi

echo "mutants: $BUDGET"
if [ "$BUDGET" -gt 0 ]; then
  if [ "$MUTANT_POOL" -eq 0 ]; then
    echo "mutant_pool: 0 — no non-styling source lines in the prod diff; the coverage stage has nothing to mutate"
  else
    echo "mutant_pool: ~$MUTANT_POOL non-styling source lines"
  fi
fi
