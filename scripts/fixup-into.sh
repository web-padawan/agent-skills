#!/usr/bin/env bash
# fixup-into.sh — fold staged or named changes into an earlier commit of the branch, then
# autosquash without an editor.
#
# Usage:
#   fixup-into.sh <sha | --grep <subject-pattern>> [<path>...] [--staged] [--no-hooks] [--autostash]
#
# The target is a commit between the merge base with the main branch and HEAD. --grep picks it
# by a case-insensitive match on the subject and requires exactly one match.
# Paths are staged with `git add -- <path>`. --staged uses the index as it is.
# --no-hooks skips the commit hooks (`-c core.hooksPath=/dev/null`).
# The rebase needs a clean tree apart from the staged changes. Other tracked changes make the
# script refuse, unless --autostash lets `git rebase --autostash` carry them.
#
# On a conflict the script aborts the rebase. The fixup commit then stays on the tip, so
# nothing is lost. Resolve by hand from there.
#
# Prints the new log of the branch and asserts that no `fixup!` commit remains.
# Exit codes: 0 ok · 1 the rebase conflicted and was aborted, or a fixup remains · 2 usage or guard.
set -euo pipefail

TARGET=""
GREP=""
PATHS=()
STAGED=false
HOOKS=()
AUTOSTASH=()

while [ $# -gt 0 ]; do
  case "$1" in
    --grep) GREP="${2:?--grep requires a value}"; shift ;;
    --staged) STAGED=true ;;
    --no-hooks) HOOKS=(-c core.hooksPath=/dev/null) ;;
    --autostash) AUTOSTASH=(--autostash) ;;
    --help|-h) sed -n '2,19p' "$0"; exit 0 ;;
    --*) echo "unknown flag: $1" >&2; exit 2 ;;
    *) if [ -z "$TARGET" ] && [ -z "$GREP" ]; then TARGET="$1"; else PATHS+=("$1"); fi ;;
  esac
  shift
done
[ -n "$TARGET" ] || [ -n "$GREP" ] || { sed -n '2,19p' "$0"; exit 2; }

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
  if [ "$COUNT" != 1 ]; then
    echo "refuse: --grep '$GREP' matched $COUNT commits in $BASE..HEAD:" >&2
    git log --oneline -i --grep="$GREP" "$BASE..HEAD" >&2
    exit 2
  fi
  TARGET="$MATCHES"
fi
TARGET=$(git rev-parse --verify --quiet "$TARGET^{commit}") || { echo "refuse: unknown commit" >&2; exit 2; }
git merge-base --is-ancestor "$TARGET" HEAD || { echo "refuse: target is not on this branch" >&2; exit 2; }
if git merge-base --is-ancestor "$TARGET" "$BASE"; then
  echo "refuse: target is on $MAIN, a fixup would rewrite shared history" >&2
  exit 2
fi
INDEX=$(git rev-list --count "$BASE..$TARGET")

if [ ${#PATHS[@]} -gt 0 ]; then
  git add -- "${PATHS[@]}"
elif [ "$STAGED" != true ]; then
  echo "refuse: name the paths to fold, or pass --staged" >&2
  exit 2
fi
git diff --cached --quiet && { echo "refuse: nothing is staged" >&2; exit 2; }

OTHER=$(git status --porcelain --untracked-files=no | grep -vE '^[MADRC] ' || true)
if [ -n "$OTHER" ] && [ ${#AUTOSTASH[@]} -eq 0 ]; then
  echo "refuse: unstaged changes would block the rebase, commit them or pass --autostash:" >&2
  printf '%s\n' "$OTHER" >&2
  git reset -q -- ${PATHS[@]+"${PATHS[@]}"} 2>/dev/null || true
  exit 2
fi

TREE_BEFORE=$(git write-tree)
git ${HOOKS[@]+"${HOOKS[@]}"} commit -q --fixup="$TARGET"
if ! GIT_SEQUENCE_EDITOR=: GIT_EDITOR=: git ${HOOKS[@]+"${HOOKS[@]}"} rebase -q -i --autosquash ${AUTOSTASH[@]+"${AUTOSTASH[@]}"} "$TARGET~1" 2>"${TMPDIR:-/tmp}/fixup-into.err"; then
  git rebase --abort 2>/dev/null || true
  echo "conflict: rebase aborted, the fixup commit stays on the tip:" >&2
  grep -E "^(CONFLICT|error: could not apply)" "${TMPDIR:-/tmp}/fixup-into.err" >&2 || true
  git log --oneline -1 >&2
  exit 1
fi

LEFT=$(git log --format=%s "$BASE..HEAD" | grep -c '^fixup!' || true)
# The rebase keeps the order, so the target sits at the same distance from the base.
NEW_TARGET=$(git rev-list --reverse "$BASE..HEAD" | sed -n "${INDEX}p")
echo "folded into: $(git log -1 --oneline "$NEW_TARGET")"
echo "tree unchanged: $([ "$(git rev-parse HEAD^{tree})" = "$TREE_BEFORE" ] && echo yes || echo no)"
echo "fixups left: $LEFT"
echo "log:"
git log --oneline "$BASE..HEAD" | sed 's/^/  /'
[ "$LEFT" = 0 ]
