#!/usr/bin/env bash
# get-pr-context.sh — Gather PR metadata, branch state, and diffs.
#
# Requires the `gh` CLI, authenticated for the current repo. Fails loudly without it.
#
# Usage:
#   get-pr-context.sh [--pr <number-or-url>] [--diff-source local|remote] [--no-diff]
#
# --no-diff skips the DIFFS section entirely — for callers whose subagents read
# the diff themselves via the ANCHORS SHAs, so the orchestrator never pays for it.
#
# When the branch is dirty and --diff-source is not explicitly set,
# the DIFFS section is skipped so the caller can ask the user first.
#
# Output sections are separated by markers for easy parsing.
set -euo pipefail

PR=""
DIFF_SOURCE=""
NO_DIFF=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --pr) PR="${2:?--pr requires a value}"; shift 2 ;;
    --diff-source) DIFF_SOURCE="${2:?--diff-source requires a value}"; shift 2 ;;
    --no-diff) NO_DIFF=true; shift ;;
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

# Extract fields with gh's own --jq, never by grepping PR_JSON: the body field
# precedes several keys alphabetically, so a PR body containing crafted JSON
# text could otherwise pre-empt them (these values feed git fetch/diff).
SOURCE_BRANCH=""
TARGET_BRANCH=""
HEAD_OID=""
PR_NUMBER=""
if [ -n "$PR_JSON" ]; then
  META=$(gh pr view ${PR_ARGS[@]+"${PR_ARGS[@]}"} --json number,headRefName,baseRefName,headRefOid \
    --jq '[.number, .headRefName, .baseRefName, .headRefOid] | @tsv' 2>/dev/null || true)
  IFS=$'\t' read -r PR_NUMBER SOURCE_BRANCH TARGET_BRANCH HEAD_OID <<< "$META"
  # Validate before use — these reach git fetch / git diff.
  case "$PR_NUMBER" in *[!0-9]*|"") PR_NUMBER="" ;; esac
  case "$HEAD_OID" in *[!0-9a-f]*|"") HEAD_OID="" ;; esac
fi

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
    # Only TRACKED changes make a branch dirty. Untracked files are reported but
    # never set the status: a stray scratch file or an unregistered skill dir is
    # not a reason to withhold the diff, and the callers' own guards
    # (review-plan.sh) already test tracked dirtiness with --untracked-files=no.
    UNCOMMITTED=$(git status --porcelain --untracked-files=no 2>/dev/null || echo "")
    UNTRACKED=$(git ls-files --others --exclude-standard --directory 2>/dev/null || echo "")

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
    if [ -n "$UNTRACKED" ]; then
      echo "untracked (does not affect status):"
      printf '%s\n' "$UNTRACKED" | sed 's/^/?? /'
    fi
  fi
fi

# ── Section: anchors ──────────────────────────────────────────────────
# Literal SHAs for callers that hand the diff to subagents: every subagent can
# run `git diff <merge_base>..<head>` from these without the branch checked out.
echo ""
echo "=== ANCHORS ==="

# Resolve the head commit: the PR's head OID when a PR exists, else local HEAD.
ANCHOR_HEAD=""
if [ -n "$HEAD_OID" ]; then
  if ! git cat-file -e "$HEAD_OID^{commit}" 2>/dev/null; then
    # Not in the local object store — fetch the PR head ref (works for forks too).
    if [ -n "$PR_NUMBER" ]; then
      git fetch origin "pull/$PR_NUMBER/head" --quiet 2>/dev/null || true
    fi
  fi
  if git cat-file -e "$HEAD_OID^{commit}" 2>/dev/null; then
    ANCHOR_HEAD="$HEAD_OID"
  fi
fi
HEAD_SOURCE="pr"
if [ -z "$ANCHOR_HEAD" ] && git rev-parse --verify HEAD >/dev/null 2>&1; then
  # No PR head available (no PR, offline, or deleted head ref) — anchor on local HEAD.
  ANCHOR_HEAD=$(git rev-parse HEAD)
  HEAD_SOURCE="local"
fi

# Resolve the base branch: the PR's base when known, else origin/main|master.
ANCHOR_BASE_BRANCH="$TARGET_BRANCH"
if [ -z "$ANCHOR_BASE_BRANCH" ]; then
  if git rev-parse --verify origin/main >/dev/null 2>&1; then
    ANCHOR_BASE_BRANCH="main"
  elif git rev-parse --verify origin/master >/dev/null 2>&1; then
    ANCHOR_BASE_BRANCH="master"
  fi
fi

MERGE_BASE=""
if [ -n "$ANCHOR_HEAD" ] && [ -n "$ANCHOR_BASE_BRANCH" ]; then
  git fetch origin "$ANCHOR_BASE_BRANCH" --quiet 2>/dev/null || true
  MERGE_BASE=$(git merge-base "origin/$ANCHOR_BASE_BRANCH" "$ANCHOR_HEAD" 2>/dev/null || true)
fi

if [ -n "$MERGE_BASE" ]; then
  echo "base_branch: $ANCHOR_BASE_BRANCH"
  echo "merge_base: $MERGE_BASE"
  echo "head: $ANCHOR_HEAD"
  if [ -n "$HEAD_OID" ] && [ "$HEAD_SOURCE" = "local" ]; then
    echo "head_source: local (PR head unavailable)"
  fi
  echo "changed_files:"
  git diff --name-only --no-renames "$MERGE_BASE..$ANCHOR_HEAD" 2>/dev/null | sed 's/^/  /' || true
  echo "diffstat:"
  git diff --stat "$MERGE_BASE..$ANCHOR_HEAD" 2>/dev/null | sed 's/^/  /' || true
else
  echo "error: cannot resolve merge base"
  echo "hint: fetch the PR head (git fetch origin pull/<n>/head) or check the base branch, then re-run"
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

if [ "$NO_DIFF" = true ]; then
  echo "skipped: true"
  echo "reason: --no-diff — subagents read the diff via the ANCHORS SHAs"
  if [ "$DIFF_SOURCE_EXPLICIT" = true ]; then
    echo "note: --diff-source is ignored with --no-diff"
  fi
  exit 0
fi

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
