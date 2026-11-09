#!/usr/bin/env bash
# plan-baseline.sh: capture the output of scripts/review-plan.sh of this checkout on
# eight fixed cases, so that a refactor of the plan script proves itself with an empty
# `diff -r` between two captures.
#
# Usage:
#   plan-baseline.sh capture <dir>
#
# Cases (self mode runs on a local branch at a pinned head, pr mode on the live PR):
#   S1 to S5  modernweb-dev/web in $BASEWT, self mode, --no-context --fresh --type <type>
#   V1        vaadin/web-components #13375 in $VWCWT, self mode, --no-context --fresh
#   P1        pr mode on modernweb-dev/web #3178 (a fork PR), with context
#   P2        pr mode on modernweb-dev/web #3194 (a merged workflow-only PR), with context
#
# Each case writes <dir>/<case>/plan.txt (stdout, stderr and the exit code), context.md,
# any patch file beside it, and `fork-marker: yes|no`. The tool replaces the context path
# with <CTX>, the cache directory with <CACHE>, and each `age=` value with <AGE>.
#
# It runs with a temporary XDG_CACHE_HOME and an empty REVIEW_SKILLS_CONFIG_DIR. It keeps
# XDG_CONFIG_HOME, because gh reads its login from there. It refuses a
# missing SHA or a moved merge base, and an EXIT trap returns each worktree to its start
# commit and deletes the local branches that it created.
#
# Env: BASEWT (default /Users/serhii/cf/modernweb-baseline),
#      VWCWT (default /Users/serhii/vaadin/web-components-baseline).
#
# Exit codes: 0 ok, 1 usage or refused case.
set -euo pipefail

BASEWT="${BASEWT:-/Users/serhii/cf/modernweb-baseline}"
VWCWT="${VWCWT:-/Users/serhii/vaadin/web-components-baseline}"
PLAN="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/review-plan.sh"
BRANCH_PREFIX="plan-baseline"

case "${1:-}" in
  capture) OUT="${2:?capture requires a directory}" ;;
  --help|-h) sed -n '2,/^set -euo pipefail$/{/^set /d;p;}' "$0"; exit 0 ;;
  *) echo "Usage: plan-baseline.sh capture <dir>" >&2; exit 1 ;;
esac

# id | worktree | mode | head or PR | merge base prefix | extra flags
CASES="S1|$BASEWT|self|215d309|48247783a1|--type chore
S2|$BASEWT|self|6672f8a|67bd94a338|--type fix
S3|$BASEWT|self|2261605|a636211dfb|--type fix
S4|$BASEWT|self|5f20860|cfc9c80b4c|--type feature
S5|$BASEWT|self|0a1e9eb|a636211dfb|--type chore
V1|$VWCWT|self|cc241cd9397f|a18937e610|
P1|$BASEWT|pr|3178||
P2|$BASEWT|pr|3194||"

WORK=$(mktemp -d)
export XDG_CACHE_HOME="$WORK/cache"
export REVIEW_SKILLS_CONFIG_DIR="$WORK/config/review"
mkdir -p "$XDG_CACHE_HOME" "$REVIEW_SKILLS_CONFIG_DIR"

START_BASE=$(git -C "$BASEWT" rev-parse HEAD)
START_VWC=$(git -C "$VWCWT" rev-parse HEAD)
restore() {
  git -C "$BASEWT" switch -q --detach "$START_BASE" 2>/dev/null || true
  git -C "$VWCWT" switch -q --detach "$START_VWC" 2>/dev/null || true
  for wt in "$BASEWT" "$VWCWT"; do
    git -C "$wt" for-each-ref --format='%(refname:short)' "refs/heads/$BRANCH_PREFIX/" \
      | while read -r b; do git -C "$wt" branch -q -D "$b" >/dev/null 2>&1 || true; done
  done
  rm -rf "$WORK"
}
trap restore EXIT

for wt in "$BASEWT" "$VWCWT"; do
  [ -z "$(git -C "$wt" status --porcelain)" ] || { echo "error: $wt is not clean" >&2; exit 1; }
done

normalize() {  # normalize <file> — replace the run-specific parts
  sed -e "s#$WORK/ctx#<CTX>#g" -e "s#$XDG_CACHE_HOME#<CACHE>#g" \
      -e 's/age=[^ ,)]*/age=<AGE>/g' "$1" > "$1.tmp" && mv "$1.tmp" "$1"
}

mkdir -p "$OUT"
while IFS='|' read -r id wt mode ref mb flags; do
  [ -n "$id" ] || continue
  dir="$OUT/$id"; ctx="$WORK/ctx/$id"
  rm -rf "$dir"; mkdir -p "$dir" "$ctx"
  rm -f "$XDG_CACHE_HOME"/*/fork-review
  args=(--mode "$mode")
  if [ "$mode" = self ]; then
    sha=$(git -C "$wt" rev-parse --verify -q "$ref^{commit}") \
      || { echo "error: $id: $ref is missing in $wt (fetch the PR head)" >&2; exit 1; }
    base_branch=main; git -C "$wt" rev-parse -q --verify origin/main >/dev/null || base_branch=master
    got=$(git -C "$wt" merge-base "origin/$base_branch" "$sha")
    case "$got" in "$mb"*) ;; *) echo "error: $id: merge base moved to ${got:0:10}, expected $mb" >&2; exit 1 ;; esac
    git -C "$wt" switch -q -C "$BRANCH_PREFIX/$(printf '%s' "$id" | tr 'A-Z' 'a-z')" "$sha"
    args+=(--no-context --fresh)
  else
    git -C "$wt" switch -q --detach "$START_BASE"
    args+=(--pr "$ref")
  fi
  # shellcheck disable=SC2206
  [ -n "$flags" ] && args+=($flags)
  args+=(--context-out "$ctx/context.md")
  set +e
  (cd "$wt" && "$PLAN" "${args[@]}") > "$dir/plan.txt" 2>&1
  code=$?
  set -e
  echo "exit: $code" >> "$dir/plan.txt"
  for f in "$ctx"/*; do [ -f "$f" ] && cp "$f" "$dir/"; done
  if ls "$XDG_CACHE_HOME"/*/fork-review >/dev/null 2>&1; then echo "fork-marker: yes"; else echo "fork-marker: no"; fi > "$dir/fork-marker"
  for f in "$dir"/*; do normalize "$f"; done
  echo "$id: exit $code, $(wc -l < "$dir/plan.txt" | tr -d ' ') plan lines"
done <<< "$CASES"
