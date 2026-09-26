#!/usr/bin/env bash
# smoke.sh — exercise the scripts that rewrite a working tree, inside a throwaway repository.
#
# Usage:
#   smoke.sh
#
# Builds a git repository under ${TMPDIR:-/tmp}/smoke-<time> with a main branch and a feature
# branch of three commits. Then runs ab.sh, fixup-into.sh and float-to-tip.sh against it and
# checks their exit codes and their effect on the tree. Also checks that every script in this
# directory answers --help with exit 0.
#
# Exit codes: 0 all checks passed · 1 a check failed.
set -uo pipefail

SCRIPTS=$(cd "$(dirname "$0")" && pwd)
WORK="${TMPDIR:-/tmp}/smoke-$(date +%Y%m%d-%H%M%S)"
WORK="${WORK//\/\//\/}"
FAILED=0

check() {
  # $1 description, $2 expected exit code, then the command
  local desc="$1" want="$2" got
  shift 2
  "$@" > "$WORK/last.log" 2>&1
  got=$?
  if [ "$got" = "$want" ]; then
    echo "ok    $desc"
  else
    echo "FAIL  $desc (exit $got, want $want)"
    sed 's/^/      | /' "$WORK/last.log" | tail -12
    FAILED=$((FAILED + 1))
  fi
}

expect() {
  # $1 description, $2 expected text, $3 actual text
  if [ "$2" = "$3" ]; then
    echo "ok    $1"
  else
    echo "FAIL  $1 (got '$3', want '$2')"
    FAILED=$((FAILED + 1))
  fi
}

mkdir -p "$WORK"
echo "work: $WORK"

echo "== help"
for f in "$SCRIPTS"/*.sh; do
  case "$(basename "$f")" in smoke.sh) continue ;; esac
  check "$(basename "$f") --help" 0 "$f" --help
done
for f in "$SCRIPTS"/probe.cjs "$SCRIPTS"/probe-compare.cjs; do
  check "$(basename "$f") --help" 0 node "$f" --help
done

echo "== repository"
REPO="$WORK/repo"
git init -q -b main "$REPO"
cd "$REPO" || exit 1
git config user.email smoke@example.com
git config user.name smoke
git config commit.gpgsign false
git config rebase.autosquash true
printf 'one\n' > a.txt
git add a.txt && git commit -q -m "base"
git checkout -q -b feature
printf 'one\ntwo\n' > a.txt && git commit -qam "add two"
printf 'x\n' > b.txt && git add b.txt && git commit -q -m "add b"
printf 'one\ntwo\nthree\n' > a.txt && git commit -qam "add three"
TREE=$(git rev-parse 'HEAD^{tree}')

echo "== ab.sh"
check "ab.sh differs when the ref changes the output" 1 \
  "$SCRIPTS/ab.sh" --ref main --path a.txt -- cat a.txt
expect "ab.sh restored the path" "" "$(git status --porcelain)"
check "ab.sh identical when the command ignores the path" 0 \
  "$SCRIPTS/ab.sh" --ref main --path a.txt -- cat b.txt
check "ab.sh refuses an unknown ref" 2 \
  "$SCRIPTS/ab.sh" --ref nope --path a.txt -- cat a.txt
printf 'dirty\n' >> a.txt
check "ab.sh refuses a dirty path" 2 \
  "$SCRIPTS/ab.sh" --ref main --path a.txt -- cat a.txt
git checkout -q -- a.txt

echo "== fixup-into.sh"
printf 'x\ny\n' > b.txt
check "fixup-into.sh folds a path into an earlier commit" 0 \
  "$SCRIPTS/fixup-into.sh" --grep "add b" b.txt
expect "fixup-into.sh kept three commits" "3" "$(git rev-list --count main..HEAD)"
expect "fixup-into.sh put y into the add b commit" "x
y" "$(git show "$(git log --format=%H --grep='add b' main..HEAD)":b.txt)"
expect "fixup-into.sh left no fixup commit" "0" "$(git log --format=%s main..HEAD | grep -c '^fixup!')"
check "fixup-into.sh refuses a commit on main" 2 \
  "$SCRIPTS/fixup-into.sh" main --staged
check "fixup-into.sh refuses when nothing is staged" 2 \
  "$SCRIPTS/fixup-into.sh" --grep "add b" --staged
printf 'one\nTWO\n' > a.txt
check "fixup-into.sh aborts on a conflict" 1 \
  "$SCRIPTS/fixup-into.sh" --grep "add two" a.txt
expect "fixup-into.sh kept the fixup on the tip" "fixup! add two" "$(git log -1 --format=%s)"
git reset -q --hard HEAD~1

echo "== float-to-tip.sh"
TREE=$(git rev-parse 'HEAD^{tree}')
check "float-to-tip.sh moves a commit to the tip" 0 \
  "$SCRIPTS/float-to-tip.sh" --grep "add b"
expect "float-to-tip.sh tip is add b" "add b" "$(git log -1 --format=%s)"
expect "float-to-tip.sh tree unchanged" "$TREE" "$(git rev-parse 'HEAD^{tree}')"
check "float-to-tip.sh reports nothing to do on the tip" 0 \
  "$SCRIPTS/float-to-tip.sh" --grep "add b"
check "float-to-tip.sh aborts on a conflict" 1 \
  "$SCRIPTS/float-to-tip.sh" --grep "add two"
expect "float-to-tip.sh branch unchanged after abort" "add b" "$(git log -1 --format=%s)"
printf 'dirty\n' >> a.txt
check "float-to-tip.sh refuses a dirty tree" 2 \
  "$SCRIPTS/float-to-tip.sh" --grep "add three"
git checkout -q -- a.txt

if [ "$FAILED" = 0 ]; then
  echo "RESULT: ok"
  rm -rf "$WORK"
  exit 0
fi
echo "RESULT: FAIL ($FAILED check(s) failed), files kept in $WORK"
exit 1
