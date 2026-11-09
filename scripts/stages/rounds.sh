#!/usr/bin/env bash
# rounds.sh: the stage script of the `rounds` stage. A round is one fan-out of the passes.
# It prints the round of this run, so that self-review knows whether to run one more.
#
# Usage:
#   rounds.sh --base <sha> --head <sha> --budget <n>
#
# review-plan.sh runs it from the repository root, per the stage contract of
# docs/contracts.md. STAGE_FINDINGS names the findings file of the branch when the plan
# read it. A file of the same head without `verdict` is a run that did not finish, so the
# round is its `round` plus 1. A file with `verdict`, a file of another head, or no file
# starts a new run at round 1.
#
# It prints `round: <k> of <n>`. Steps: skills/self-review/references/rounds.md.
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
[[ "$HEAD" =~ ^[0-9a-f]{7,40}$ ]] || { echo "error: --head takes a commit SHA" >&2; exit 2; }
[[ "$BUDGET" =~ ^[0-9]+$ ]] || { echo "error: --budget takes a number" >&2; exit 2; }

ROUND=1
FILE="${STAGE_FINDINGS:-}"
if [ -n "$FILE" ] && [ -f "$FILE" ] \
  && jq -e --arg head "$HEAD" '.head == $head and (has("verdict") | not)' "$FILE" >/dev/null 2>&1; then
  ROUND=$(( $(jq -r '.round // 1' "$FILE") + 1 ))
fi
echo "round: $ROUND of $BUDGET"
