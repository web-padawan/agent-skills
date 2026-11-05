#!/usr/bin/env bash
# pr-refresh.sh — What changed on a PR since its review plan ran: the head, the tree, CI and
# the comments. pr-review runs it before the gate question and before triage. A push or a
# bot review during a run otherwise goes unseen until post-review.sh refuses or skips
# (retrospective, PR review 7).
#
# Usage:
#   pr-refresh.sh --context <context file of review-plan.sh>
#
# The context file gives the PR (`- pr:`), the head that the plan read (`- head:`) and the
# ids of the comments under `## Already on the PR`. The script reads the current state with
# get-pr-context.sh --no-diff. It fetches the new head into the object store and never
# checks it out, so it is safe on a fork head.
#
# Prints:
#   head: <current head SHA>
#   head_moved: no | yes, <n> commits on top of <old> | yes, rewritten (<old> is not an ancestor)
#   base_moved: <old> -> <new>                (only when the merge base moved)
#   tree_changed: no | unknown | <n> files: <paths>, the files whose own PR diff differs.
#     Each head is diffed against its merge base, so a merge of the base branch is no change.
#   ci: <the summary line of the current CI>
#   new_threads: none | the new threads and replies, in the format of the context file
#   new_general: none | the new general comments
#   action: <the next step for each change>
#
# Exit codes: 0 ok · 1 gh or git could not answer · 2 usage error.
set -euo pipefail

CONTEXT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --context) CONTEXT="${2:?--context requires a value}"; shift 2 ;;
    --help|-h) sed -n '2,/^set -euo pipefail$/{/^set /d;p;}' "$0"; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done

[ -n "$CONTEXT" ] || { echo "error: --context is required" >&2; exit 2; }
[ -f "$CONTEXT" ] || { echo "error: no context file at $CONTEXT" >&2; exit 2; }
command -v gh >/dev/null 2>&1 || { echo "error: gh CLI not found" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "error: jq not found" >&2; exit 1; }
git rev-parse --git-dir >/dev/null 2>&1 || { echo "error: not a git repository" >&2; exit 1; }

PR=$(sed -n 's/^- pr: \(https:[^ ]*\)$/\1/p' "$CONTEXT" | head -1)
OLD=$(sed -n 's/^- head: `\([0-9a-f]\{40\}\)`.*/\1/p' "$CONTEXT" | head -1)
[ -n "$PR" ] || { echo "error: the context file names no PR (\`- pr:\`); it is not a pr-mode context" >&2; exit 2; }
[ -n "$OLD" ] || { echo "error: the context file names no head (\`- head:\`)" >&2; exit 2; }

# The ids that the plan already listed: thread roots, replies and general comments.
KNOWN=$(awk '/^## Already on the PR$/ { f = 1; next } /^## / { f = 0 } f' "$CONTEXT" \
  | sed -n -E 's/^[[:space:]]+(reply )?([0-9]+) \|.*/\2/p' | sort -u)

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
CTX=$("$SCRIPT_DIR/get-pr-context.sh" --pr "$PR" --no-diff 2>/dev/null) \
  || { echo "error: get-pr-context.sh could not read $PR" >&2; exit 1; }
section() { printf '%s\n' "$CTX" | awk -v s="=== $1 ===" '$0 == s { f = 1; next } /^=== / { f = 0 } f'; }

# get-pr-context.sh exits 0 when gh fails, with the error text in PR_METADATA.
NEW=$(section PR_METADATA | sed '/^$/d' | jq -r '.headRefOid // empty' 2>/dev/null | head -1 || true)
[[ "$NEW" =~ ^[0-9a-f]{40}$ ]] || {
  echo "error: no head SHA for $PR: $(section PR_METADATA | sed '/^$/d' | head -1 | cut -c1-200)" >&2; exit 1; }
SLUG=$(printf '%s' "$PR" | sed -n 's|^https://[^/]*/\([^/]*/[^/]*\)/pull/.*|\1|p')
NUMBER=${PR##*/}

OLD_BASE=$(sed -n 's/^- base: `\([0-9a-f]\{40\}\)`.*/\1/p' "$CONTEXT" | head -1)
NEW_BASE=$(section ANCHORS | sed -n 's/^merge_base: \([0-9a-f]\{40\}\)$/\1/p' | head -1)

have() {  # have <sha>: the commit is in the object store, fetched if needed
  git cat-file -e "$1^{commit}" 2>/dev/null && return 0
  git fetch -q --no-tags "https://github.com/$SLUG.git" "$1" 2>/dev/null \
    || git fetch -q --no-tags "https://github.com/$SLUG.git" "pull/$NUMBER/head" 2>/dev/null || true
  git cat-file -e "$1^{commit}" 2>/dev/null
}
# The files whose own PR diff differs between the two heads. Each side is diffed against
# its merge base, so a merge of the base branch into the PR does not count as a change.
own_diff_changes() {
  local f
  { git diff --name-only "$OLD_BASE" "$OLD"; git diff --name-only "$NEW_BASE" "$NEW"; } | sort -u \
    | while IFS= read -r f; do
        cmp -s <(git diff "$OLD_BASE" "$OLD" -- "$f" | grep -v '^index ') \
               <(git diff "$NEW_BASE" "$NEW" -- "$f" | grep -v '^index ') || printf '%s\n' "$f"
      done
}

ACTIONS=()
RERUN="the plan read another diff: before the fan-out, re-run review-plan.sh; after it, verify each finding at ${NEW:0:7} (pipeline.md §5.1)"
echo "=== REFRESH ==="
echo "head: $NEW"
if [ "$NEW" = "$OLD" ]; then
  echo "head_moved: no"
  echo "tree_changed: no"
elif ! have "$NEW" || ! have "$OLD"; then
  echo "head_moved: yes, ${OLD:0:7} or ${NEW:0:7} is not available locally"
  echo "tree_changed: unknown"
  ACTIONS+=("$RERUN")
else
  if git merge-base --is-ancestor "$OLD" "$NEW"; then
    echo "head_moved: yes, $(git rev-list --count "$OLD..$NEW") commits on top of ${OLD:0:7}"
    git log --format='  %h %s' "$OLD..$NEW"
  else
    echo "head_moved: yes, rewritten (${OLD:0:7} is not an ancestor)"
  fi
  if [ -z "$OLD_BASE" ] || [ -z "$NEW_BASE" ] || ! have "$OLD_BASE" || ! have "$NEW_BASE"; then
    echo "tree_changed: unknown (no merge base to compare the diffs of the PR)"
    ACTIONS+=("$RERUN")
  else
    [ "$OLD_BASE" != "$NEW_BASE" ] && echo "base_moved: ${OLD_BASE:0:7} -> ${NEW_BASE:0:7} (not counted as a change)"
    CHANGED=$(own_diff_changes)
    if [ -z "$CHANGED" ]; then
      echo "tree_changed: no"
      ACTIONS+=("keep the plan: the diff of the PR is the same, so every anchor holds")
    else
      echo "tree_changed: $(printf '%s\n' "$CHANGED" | wc -l | tr -d ' ') files: $(printf '%s\n' "$CHANGED" | paste -sd' ' -)"
      ACTIONS+=("$RERUN")
    fi
  fi
fi

CI=$(section CI_STATUS | sed -n 's/^summary: //p' | head -1)
echo "ci: ${CI:-unknown}"

# The current comments, minus the ids that the plan listed. A reply prints under its root,
# so a new reply in an old thread names that thread.
COMMENTS=$(section EXISTING_COMMENTS)
NEW_THREADS=$(printf '%s\n' "$COMMENTS" | awk -v known="$(printf '%s\n' "$KNOWN" | paste -sd' ' -)" '
  BEGIN { n = split(known, k, " "); for (i = 1; i <= n; i++) seen[k[i]] = 1 }
  /^threads:/ { t = 1; g = 0; next }
  /^general:/ { t = 0; g = 0; next }
  /^[a-z_]+:/ { t = 0; next }
  t && /^  [0-9]+ \|/ { id = $1; root = $0; printed = 0
    if (!(id in seen)) { print root; printed = 1 } ; next }
  t && /^      reply [0-9]+ \|/ { id = $2
    if (!(id in seen)) { if (!printed) { print root " (thread known)"; printed = 1 } print } }')
NEW_GENERAL=$(printf '%s\n' "$COMMENTS" | awk -v known="$(printf '%s\n' "$KNOWN" | paste -sd' ' -)" '
  BEGIN { n = split(known, k, " "); for (i = 1; i <= n; i++) seen[k[i]] = 1 }
  /^general:/ { g = 1; next }
  /^[a-z_]+:/ { g = 0; next }
  g && /^  [0-9]+ \|/ { if (!($1 in seen)) print }')
if [ -n "$NEW_THREADS" ]; then
  echo "new_threads:"
  printf '%s\n' "$NEW_THREADS"
  ACTIONS+=("dedup against the new threads too, and read each new reply before a finding repeats or answers its thread (pipeline.md §5.2)")
else
  echo "new_threads: none"
fi
if [ -n "$NEW_GENERAL" ]; then
  echo "new_general:"
  printf '%s\n' "$NEW_GENERAL"
  ACTIONS+=("read each new general comment: a bot can post its review summary there")
else
  echo "new_general: none"
fi

if [ "${#ACTIONS[@]}" -eq 0 ]; then
  echo "action: none, the plan is current"
else
  for a in "${ACTIONS[@]}"; do echo "action: $a"; done
fi
