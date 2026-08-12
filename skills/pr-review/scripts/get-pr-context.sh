#!/usr/bin/env bash
# get-pr-context.sh — Gather PR metadata, branch state, and diffs.
#
# Requires the `gh` CLI, authenticated for the current repo. Fails loudly without it.
#
# Usage:
#   get-pr-context.sh [--pr <number-or-url>] [--diff-source local|remote]
#
# When the branch is dirty and --diff-source is not explicitly set,
# the DIFFS section is skipped so the caller can ask the user first.
#
# Output sections are separated by markers for easy parsing.
set -euo pipefail

PR=""
DIFF_SOURCE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --pr) PR="${2:?--pr requires a value}"; shift 2 ;;
    --diff-source) DIFF_SOURCE="${2:?--diff-source requires a value}"; shift 2 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

DIFF_SOURCE_EXPLICIT=true
if [ -z "$DIFF_SOURCE" ]; then
  DIFF_SOURCE="remote"
  DIFF_SOURCE_EXPLICIT=false
elif [ "$DIFF_SOURCE" != "local" ] && [ "$DIFF_SOURCE" != "remote" ]; then
  echo "error: --diff-source must be 'local' or 'remote' (got '$DIFF_SOURCE')" >&2
  exit 1
fi

# Diffs and instruction-file checks are repo-root-relative; do not depend on the caller's cwd.
cd "$(git rev-parse --show-toplevel)"

if ! command -v gh >/dev/null 2>&1; then
  echo "error: gh CLI not found — this skill requires it" >&2
  echo "hint: install from https://cli.github.com and run 'gh auth login'" >&2
  exit 1
fi

PR_ARGS=()
if [ -n "$PR" ]; then
  PR_ARGS+=("$PR")
fi

# ── Section: PR metadata ─────────────────────────────────────────────
echo "=== PR_METADATA ==="

PR_JSON=""
if PR_JSON=$(gh pr view ${PR_ARGS[@]+"${PR_ARGS[@]}"} --json number,title,body,author,state,isDraft,baseRefName,headRefName,headRefOid,url 2>/dev/null); then
  echo "$PR_JSON"
else
  PR_JSON=""
  echo "error: failed to resolve the PR"
  if [ -n "$PR" ]; then
    echo "hint: check the PR number/URL and that gh is authenticated for this repo"
  else
    echo "hint: the current branch has no open PR — pass --pr <number-or-url>"
  fi
fi

json_field() {
  # json_field <key> — extract a top-level string field from PR_JSON without jq.
  # `|| true` keeps a missing field from killing the script under pipefail+errexit.
  echo "$PR_JSON" | grep -o "\"$1\":\"[^\"]*\"" | head -1 | cut -d'"' -f4 || true
}

SOURCE_BRANCH=$(json_field headRefName)
TARGET_BRANCH=$(json_field baseRefName)

# ── Section: branch state ────────────────────────────────────────────
echo ""
echo "=== BRANCH_STATE ==="

BRANCH_STATUS="CLEAN"
CURRENT_BRANCH=$(git branch --show-current 2>/dev/null || echo "")

if [ -z "$CURRENT_BRANCH" ]; then
  BRANCH_STATUS="DETACHED_HEAD"
  echo "status: $BRANCH_STATUS"
  echo "branch: (detached)"
else
  echo "branch: $CURRENT_BRANCH"

  if [ -n "$SOURCE_BRANCH" ] && [ "$CURRENT_BRANCH" != "$SOURCE_BRANCH" ]; then
    BRANCH_STATUS="NOT_CHECKED_OUT"
    echo "status: $BRANCH_STATUS"
    echo "source_branch: $SOURCE_BRANCH"
  else
    git fetch origin "$CURRENT_BRANCH" --quiet 2>/dev/null || true

    LOCAL_HEAD=$(git rev-parse HEAD 2>/dev/null || echo "unknown")
    if git rev-parse --verify "origin/$CURRENT_BRANCH" >/dev/null 2>&1; then
      REMOTE_HEAD=$(git rev-parse "origin/$CURRENT_BRANCH")
    else
      REMOTE_HEAD="not_on_remote"
    fi
    UNCOMMITTED=$(git status --porcelain 2>/dev/null || echo "")

    LOCAL_SHORT="${LOCAL_HEAD:0:8}"
    if [ "$REMOTE_HEAD" = "not_on_remote" ]; then
      REMOTE_SHORT="not_on_remote"
    else
      REMOTE_SHORT="${REMOTE_HEAD:0:8}"
    fi

    if [ "$LOCAL_HEAD" != "$REMOTE_HEAD" ] && [ -n "$UNCOMMITTED" ]; then
      BRANCH_STATUS="DIVERGED_AND_DIRTY"
    elif [ "$LOCAL_HEAD" != "$REMOTE_HEAD" ]; then
      BRANCH_STATUS="UNPUSHED_COMMITS"
    elif [ -n "$UNCOMMITTED" ]; then
      BRANCH_STATUS="UNCOMMITTED_CHANGES"
    fi

    echo "status: $BRANCH_STATUS"
    echo "local_head: $LOCAL_SHORT"
    echo "remote_head: $REMOTE_SHORT"
    if [ -n "$UNCOMMITTED" ]; then
      echo "uncommitted:"
      echo "$UNCOMMITTED"
    fi
  fi
fi

# ── Section: review instructions ──────────────────────────────────────
echo ""
echo "=== REVIEW_INSTRUCTIONS ==="

if [ -f .github/review-instructions.md ]; then
  cat .github/review-instructions.md
elif [ -f .github/copilot-instructions.md ]; then
  cat .github/copilot-instructions.md
else
  echo "none"
  for f in CONVENTIONS.md CLAUDE.md AGENTS.md; do
    if [ -f "$f" ]; then
      echo "hint: $f exists — read its conventions before reviewing"
    fi
  done
fi

# ── Section: diffs ────────────────────────────────────────────────────
echo ""
echo "=== DIFFS ==="

# If the branch is dirty and the user hasn't explicitly chosen a diff source,
# skip diffs so the caller can present the choice to the user first.
IS_DIRTY=false
case "$BRANCH_STATUS" in
  UNPUSHED_COMMITS|UNCOMMITTED_CHANGES|DIVERGED_AND_DIRTY) IS_DIRTY=true ;;
esac

if [ "$IS_DIRTY" = true ] && [ "$DIFF_SOURCE_EXPLICIT" = false ]; then
  echo "skipped: true"
  echo "reason: branch is dirty — ask the user whether to review remote or local diff"
  echo "hint: re-run with --diff-source local or --diff-source remote"
  exit 0
fi

if [ "$DIFF_SOURCE" = "local" ]; then
  if [ -z "$TARGET_BRANCH" ]; then
    # Fallback: assume main or master
    if git rev-parse --verify origin/main >/dev/null 2>&1; then
      TARGET_BRANCH="main"
    elif git rev-parse --verify origin/master >/dev/null 2>&1; then
      TARGET_BRANCH="master"
    else
      echo "error: cannot determine target branch for local diff"
      echo "hint: pass --pr <number-or-url>, or use remote diff instead"
      exit 1
    fi
  fi

  echo "source: local"
  echo "target_branch: $TARGET_BRANCH"
  echo "---"
  git diff "origin/$TARGET_BRANCH"...HEAD -- . \
    ':!*.lock' ':!vendor/' ':!node_modules/' ':!*.min.js' ':!*.min.css' \
    ':!package-lock.json' ':!yarn.lock' ':!bun.lockb' ':!pnpm-lock.yaml'
else
  echo "source: remote (gh)"
  echo "---"
  gh pr diff ${PR_ARGS[@]+"${PR_ARGS[@]}"} 2>/dev/null || {
    echo "error: gh pr diff failed"
    echo "hint: check the PR number and gh authentication"
  }
fi
