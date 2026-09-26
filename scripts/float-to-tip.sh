#!/usr/bin/env bash
# float-to-tip.sh — move one commit of the branch to the tip, keep every other commit in order.
#
# Usage:
#   float-to-tip.sh <sha | --grep <subject-pattern>> [--autostash]
#
# The commit must sit between the merge base with the main branch and HEAD. --grep picks it
# by a case-insensitive subject match and requires exactly one match.
# The tree needs to be clean, unless --autostash lets `git rebase --autostash` carry changes.
# On a conflict the script aborts the rebase and leaves the branch as it was.
#
# Asserts that the final tree equals the tree before the move, so the reorder changed no
# content. Prints the new log of the branch.
# Exit codes: 0 ok · 1 the rebase conflicted and was aborted, or the tree changed · 2 usage or guard.
set -euo pipefail

if [ "${1:-}" = "--todo" ]; then
  # Sequence editor mode: move the line of $2 (full sha) to the end of the todo file $3.
  WANT="$2"; FILE="$3"
  KEEP=$(mktemp); MOVE=$(mktemp)
  while IFS= read -r line; do
    if [[ "$line" =~ ^(pick|p)\ ([0-9a-f]+) ]] && [ "$(git rev-parse --verify --quiet "${BASH_REMATCH[2]}^{commit}")" = "$WANT" ]; then
      printf '%s\n' "$line" >> "$MOVE"
    else
      printf '%s\n' "$line" >> "$KEEP"
    fi
  done < "$FILE"
  cat "$KEEP" "$MOVE" > "$FILE"
  rm -f "$KEEP" "$MOVE"
  exit 0
fi

TARGET=""
GREP=""
AUTOSTASH=()
while [ $# -gt 0 ]; do
  case "$1" in
    --grep) GREP="${2:?--grep requires a value}"; shift ;;
    --autostash) AUTOSTASH=(--autostash) ;;
    --help|-h) sed -n '2,14p' "$0"; exit 0 ;;
    --*) echo "unknown flag: $1" >&2; exit 2 ;;
    *) TARGET="$1" ;;
  esac
  shift
done
[ -n "$TARGET" ] || [ -n "$GREP" ] || { sed -n '2,14p' "$0"; exit 2; }

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "refuse: not a git repository" >&2; exit 2; }
cd "$ROOT"
MAIN=""
for m in origin/main origin/master main master; do
  if git rev-parse --verify --quiet "$m^{commit}" >/dev/null; then MAIN="$m"; break; fi
done
[ -n "$MAIN" ] || { echo "refuse: no main or master branch found" >&2; exit 2; }
BASE=$(git merge-base "$MAIN" HEAD)

if [ -n "$GREP" ]; then
  MATCHES=$(git log --format=%H -i --grep="$GREP" "$BASE..HEAD")
  COUNT=$(printf '%s\n' "$MATCHES" | sed '/^$/d' | wc -l | tr -d ' ')
  [ "$COUNT" = 1 ] || { echo "refuse: --grep '$GREP' matched $COUNT commits" >&2; git log --oneline -i --grep="$GREP" "$BASE..HEAD" >&2; exit 2; }
  TARGET="$MATCHES"
fi
TARGET=$(git rev-parse --verify --quiet "$TARGET^{commit}") || { echo "refuse: unknown commit" >&2; exit 2; }
git merge-base --is-ancestor "$TARGET" HEAD || { echo "refuse: commit is not on this branch" >&2; exit 2; }
git merge-base --is-ancestor "$TARGET" "$BASE" && { echo "refuse: commit is on $MAIN" >&2; exit 2; }
if [ "$TARGET" = "$(git rev-parse HEAD)" ]; then echo "nothing to do: the commit is the tip already"; exit 0; fi
if [ -n "$(git status --porcelain --untracked-files=no)" ] && [ ${#AUTOSTASH[@]} -eq 0 ]; then
  echo "refuse: the tree has uncommitted changes, commit them or pass --autostash" >&2
  exit 2
fi

TREE_BEFORE=$(git rev-parse 'HEAD^{tree}')
HEAD_BEFORE=$(git rev-parse HEAD)
SELF=$(cd "$(dirname "$0")" && pwd)/$(basename "$0")
if ! GIT_SEQUENCE_EDITOR="$SELF --todo $TARGET" GIT_EDITOR=: git rebase -q -i --no-autosquash ${AUTOSTASH[@]+"${AUTOSTASH[@]}"} "$BASE" 2>"${TMPDIR:-/tmp}/float-to-tip.err"; then
  git rebase --abort 2>/dev/null || true
  echo "conflict: rebase aborted, branch unchanged at $(git rev-parse --short "$HEAD_BEFORE")" >&2
  grep -E "^(CONFLICT|error: could not apply)" "${TMPDIR:-/tmp}/float-to-tip.err" >&2 || true
  exit 1
fi
echo "tip: $(git log -1 --oneline)"
echo "tree unchanged: $([ "$(git rev-parse 'HEAD^{tree}')" = "$TREE_BEFORE" ] && echo yes || echo no)"
echo "log:"
git log --oneline "$BASE..HEAD" | sed 's/^/  /'
[ "$(git rev-parse 'HEAD^{tree}')" = "$TREE_BEFORE" ]
