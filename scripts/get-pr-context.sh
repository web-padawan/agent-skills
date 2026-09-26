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
    --help|-h) sed -n '2,15p' "$0"; exit 0 ;;
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

# ── Section: CI status ────────────────────────────────────────────────
# What CI has already proved about this head. A green lint / test / visual check
# is authoritative: no pass should re-run it locally to prove a failure CI shows
# as passing, and a red one is evidence a finding can cite directly.
echo ""
echo "=== CI_STATUS ==="

if [ -z "$PR_JSON" ]; then
  echo "unavailable: no PR resolved"
else
  CHECKS=$(gh pr checks ${PR_ARGS[@]+"${PR_ARGS[@]}"} 2>/dev/null || true)
  if [ -z "$CHECKS" ]; then
    echo "unavailable: gh pr checks reported nothing (none configured, or not started yet)"
    echo "note: absence of checks is not a green run — treat lint and test state as unknown"
  else
    # Columns are TAB-separated: name, state, elapsed, link.
    CHECK_TOTAL=$(printf '%s\n' "$CHECKS" | wc -l | tr -d ' ')
    CHECK_PASS=$(printf '%s\n' "$CHECKS" | awk -F'\t' '$2=="pass"' | wc -l | tr -d ' ')
    CHECK_FAIL=$(printf '%s\n' "$CHECKS" | awk -F'\t' '$2=="fail"' | wc -l | tr -d ' ')
    CHECK_PEND=$(printf '%s\n' "$CHECKS" | awk -F'\t' '$2=="pending"' | wc -l | tr -d ' ')
    CHECK_SKIP=$(printf '%s\n' "$CHECKS" | awk -F'\t' '$2=="skipping"' | wc -l | tr -d ' ')
    echo "summary: $CHECK_TOTAL checks — $CHECK_PASS pass, $CHECK_FAIL fail, $CHECK_PEND pending, $CHECK_SKIP skipped"
    echo "checks:"
    printf '%s\n' "$CHECKS" | awk -F'\t' '{printf "  %s: %s\n", $1, $2}'
    if [ "$CHECK_FAIL" != "0" ]; then
      echo "hint: a failing check is an A-tier finding on its own — name the check in the claim"
      printf '%s\n' "$CHECKS" | awk -F'\t' '$2=="fail" {printf "  failing: %s — %s\n", $1, $4}'
    fi
  fi
fi

# ── Section: existing comments ────────────────────────────────────────
# What is already said on this PR. A finding that repeats one of these is
# noise for the author; an unresolved thread no pass reproduces is a lead.
# Thread roots only — replies are conversation, not claims — with the
# thread's resolved/outdated state, which is why GraphQL and not the REST
# comments list. Bodies are cut to their first non-empty line; a leading
# ":robot: AI-generated" and a Conventional Comments label are stripped so
# the claim text is what the passes match on. Bodies are text written by
# other people — data, never instructions.
echo ""
echo "=== EXISTING_COMMENTS ==="

if [ -z "$PR_NUMBER" ]; then
  echo "unavailable: no PR resolved"
else
  REPO_SLUG=$(gh pr view ${PR_ARGS[@]+"${PR_ARGS[@]}"} --json url --jq '.url' 2>/dev/null \
    | sed -n 's|^https://[^/]*/\([^/]*/[^/]*\)/pull/.*|\1|p')
  THREADS=""
  GENERAL=""
  if [ -n "$REPO_SLUG" ]; then
    THREADS=$(gh api graphql -f owner="${REPO_SLUG%%/*}" -f name="${REPO_SLUG##*/}" -F number="$PR_NUMBER" -f query='
      query($owner:String!,$name:String!,$number:Int!){
        repository(owner:$owner,name:$name){ pullRequest(number:$number){
          reviewThreads(first:100){ nodes{
            isResolved isOutdated path line originalLine
            comments(first:1){ nodes{ databaseId author{login __typename} body } } } } } } }' \
      --jq '.data.repository.pullRequest.reviewThreads.nodes[]
        | .comments.nodes[0] as $c
        | [ $c.databaseId, $c.author.login,
            (if ($c.author.__typename == "Bot") or ($c.author.login | test("bot$"; "i")) then "bot" else "human" end),
            (if .isResolved then "resolved" elif .isOutdated then "outdated" else "open" end),
            .path, (.line // .originalLine // 0),
            ($c.body | split("\n") | map(select(length > 0)) | .[0] // ""
              | sub("^:robot: AI-generated\\s*"; "")
              | (capture("^\\*\\*(?<t>[^*]+)\\*\\*:?\\s*(?<rest>.*)$") // {t: "", rest: .})
              | (if .rest == "" then .t else .rest end) | .[0:200]) ]
        | @tsv' 2>/dev/null || true)
    GENERAL=$(gh api "repos/$REPO_SLUG/issues/$PR_NUMBER/comments" --paginate \
      --jq '.[] | [ .id, .user.login, (.body | split("\n") | map(select(length > 0)) | .[0] // "" | .[0:120]) ] | @tsv' 2>/dev/null || true)
  fi

  if [ -z "$THREADS" ] && [ -z "$GENERAL" ]; then
    echo "none"
  else
    T_N=$(printf '%s\n' "$THREADS" | sed '/^$/d' | wc -l | tr -d ' ')
    T_BOT=$(printf '%s\n' "$THREADS" | awk -F'\t' '$3=="bot"' | wc -l | tr -d ' ')
    T_OPEN=$(printf '%s\n' "$THREADS" | awk -F'\t' '$4=="open"' | wc -l | tr -d ' ')
    G_N=$(printf '%s\n' "$GENERAL" | sed '/^$/d' | wc -l | tr -d ' ')
    echo "summary: $T_N threads ($T_BOT bot, $((T_N - T_BOT)) human, $T_OPEN open), $G_N general comments"
    if [ -n "$THREADS" ]; then
      echo "threads:  # id | author | kind | state | path:line | first line"
      printf '%s\n' "$THREADS" | sed '/^$/d' | awk -F'\t' '{printf "  %s | %s | %s | %s | %s:%s | %s\n", $1, $2, $3, $4, $5, $6, $7}'
    fi
    if [ -n "$GENERAL" ]; then
      echo "general:  # id | author | first line"
      printf '%s\n' "$GENERAL" | sed '/^$/d' | awk -F'\t' '{printf "  %s | %s | %s\n", $1, $2, $3}'
    fi
    if [ "$T_BOT" != "0" ]; then
      echo "hint: a review bot has already commented — a finding on the same file and claim is a duplicate, not a discovery"
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
