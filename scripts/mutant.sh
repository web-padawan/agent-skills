#!/usr/bin/env bash
# mutant.sh — run the tests against one mutant, restore the file, and check the clean tree.
# The coverage step of self-review (skills/self-review/references/mutation.md) edits one
# source file, then calls this script. The restore runs on every exit, including a failure.
# Only a SIGKILL skips it.
#
# Usage:
#   mutant.sh --head <sha> --file <path> [--log <path>] -- <test command> [args...]
#   mutant.sh --head <sha> --baseline [--log <path>] -- <test command> [args...]
#
# --head is head0 from the plan. The script refuses when HEAD differs from it.
# --file is the mutated file. It must be the only tracked file with a change, and nothing may
#   be staged. The restore is `git checkout -- <file>`, which resets the file to the index.
# --baseline runs the command on the clean tree, before the first mutant. A red baseline
#   makes every mutant look killed.
# --log keeps the output of the command. Default ${TMPDIR:-/tmp}/mutant-<time>.log.
# The command runs through `bash -c`, so quote it as one argument or pass it after `--`.
#
# Prints `RESULT: KILLED (exit <n>)` and the last 10 lines of the log, or `RESULT: SURVIVED`.
# With --baseline it prints `RESULT: GREEN` or `RESULT: RED (exit <n>)`. Then it prints
# `tree: clean` after the restore.
#
# Exit codes: 0 killed or green · 1 survived or red · 2 guard or usage error · 3 the tree is
# not clean after the restore.
set -uo pipefail

HEAD0=""; FILE=""; BASELINE=false; LOG=""; CMD=()
while [ $# -gt 0 ]; do
  case "$1" in
    --head) HEAD0="${2:?--head requires a value}"; shift ;;
    --file) FILE="${2:?--file requires a value}"; shift ;;
    --baseline) BASELINE=true ;;
    --log) LOG="${2:?--log requires a value}"; shift ;;
    --help|-h) sed -n '2,/^set -uo pipefail$/{/^set /d;p;}' "$0"; exit 0 ;;
    --) shift; CMD=("$@"); break ;;
    *) echo "unknown argument: $1 (put the command after --)" >&2; exit 2 ;;
  esac
  shift
done
usage() { sed -n '2,/^set -uo pipefail$/{/^set /d;p;}' "$0" >&2; exit 2; }
[ -n "$HEAD0" ] && [ ${#CMD[@]} -gt 0 ] || usage
if [ "$BASELINE" = true ]; then [ -z "$FILE" ] || usage; else [ -n "$FILE" ] || usage; fi

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "refuse: not a git repository" >&2; exit 2; }
cd "$ROOT"
HEAD_NOW=$(git rev-parse HEAD)
HEAD_WANT=$(git rev-parse --verify --quiet "$HEAD0^{commit}") || { echo "refuse: unknown commit $HEAD0" >&2; exit 2; }
[ "$HEAD_NOW" = "$HEAD_WANT" ] || { echo "refuse: HEAD is $HEAD_NOW, not head0 $HEAD_WANT" >&2; exit 2; }
STAGED=$(git diff --staged --name-only)
[ -z "$STAGED" ] || { printf 'refuse: staged files, the restore resets to the index:\n%s\n' "$STAGED" >&2; exit 2; }
DIRTY=$(git diff --name-only)
if [ "$BASELINE" = true ]; then
  [ -z "$DIRTY" ] || { printf 'refuse: the baseline needs a clean tree, dirty:\n%s\n' "$DIRTY" >&2; exit 2; }
else
  FILE=$(git ls-files --full-name -- "$FILE")
  [ -n "$FILE" ] || { echo "refuse: the mutated file is not tracked" >&2; exit 2; }
  [ "$DIRTY" = "$FILE" ] || {
    if [ -z "$DIRTY" ]; then echo "refuse: $FILE has no change, apply the mutant first" >&2
    else printf 'refuse: apply one mutant in %s only, dirty:\n%s\n' "$FILE" "$DIRTY" >&2; fi
    exit 2
  }
fi

[ -n "$LOG" ] || LOG="${TMPDIR:-/tmp}/mutant-$(date +%Y%m%d-%H%M%S).log"
LOG="${LOG//\/\//\/}"
mkdir -p "$(dirname "$LOG")"

CHILD=""
restore() {
  [ -n "$CHILD" ] && kill "$CHILD" 2>/dev/null
  [ -n "$FILE" ] && git checkout -q -- "$FILE" 2>/dev/null
  FILE=""
}
trap restore EXIT
trap 'restore; trap - EXIT; echo "interrupted: mutant restored" >&2; exit 130' INT TERM

if [ "$BASELINE" = false ]; then
  echo "mutant: $FILE"
  git diff -U0 --no-color -- "$FILE" | grep -E '^[-+][^-+]' | sed 's/^/  /'
fi
echo "command: ${CMD[*]}"
bash -c "${CMD[*]}" > "$LOG" 2>&1 &
CHILD=$!
wait "$CHILD"
CODE=$?
CHILD=""
echo "log: $LOG ($(wc -l < "$LOG" | tr -d ' ') lines)"

if [ "$BASELINE" = true ]; then
  if [ "$CODE" -eq 0 ]; then echo "RESULT: GREEN"; RC=0; else echo "RESULT: RED (exit $CODE)"; RC=1; fi
else
  restore
  if [ "$CODE" -ne 0 ]; then
    echo "RESULT: KILLED (exit $CODE)"
    tail -n 10 "$LOG" | sed 's/^/  /'
    RC=0
  else
    echo "RESULT: SURVIVED"
    RC=1
  fi
fi

LEFT=$(git status --porcelain --untracked-files=no)
if [ -n "$LEFT" ] || [ "$(git rev-parse HEAD)" != "$HEAD_WANT" ]; then
  printf 'tree: NOT CLEAN after the restore, stop the coverage step:\n%s\n' "$LEFT" >&2
  exit 3
fi
echo "tree: clean"
exit "$RC"
