#!/usr/bin/env bash
# review-plan.sh — compute the review plan for a review skill: the anchors, the
# change type, the scale tier, the pass list with its agents and read lanes, the
# mutant budget, the guards, and the report paths.
#
# The matrix it resolves lives in references/profiles.md — this script parses that
# file, so the tables are never restated in a skill.
#
# Usage:
#   review-plan.sh [--mode self|pr|arch] [--pr <number-or-url>]
#                  [--type fix|feature|refactor|chore] [--scale trivial|lite|full]
#                  [--deep N] [--no-coverage] [--report-dir <path>] [--no-context]
#
# Prints get-pr-context.sh's sections (skip with --no-context) then === PLAN ===.
# Read-only: never writes, stages, commits, or touches the working tree.
#
# Exit codes: 0 ok · 1 usage/environment error · 2 guard refused the run.
set -euo pipefail

MODE="self"
PR=""
TYPE_FLAG=""
SCALE_FLAG=""
DEEP=""
COVERAGE="on"
REPORT_DIR=""
WANT_CONTEXT=true

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode) MODE="${2:?--mode requires a value}"; shift 2 ;;
    --pr) PR="${2:?--pr requires a value}"; shift 2 ;;
    --type) TYPE_FLAG="${2:?--type requires a value}"; shift 2 ;;
    --scale) SCALE_FLAG="${2:?--scale requires a value}"; shift 2 ;;
    --deep) DEEP="${2:?--deep requires a value}"; shift 2 ;;
    --no-coverage) COVERAGE="off"; shift ;;
    --report-dir) REPORT_DIR="${2:?--report-dir requires a value}"; shift 2 ;;
    --no-context) WANT_CONTEXT=false; shift ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

case "$MODE" in self|pr|arch) ;; *) echo "error: --mode must be self, pr or arch" >&2; exit 1 ;; esac
case "$TYPE_FLAG" in ""|fix|feature|refactor|chore) ;; *) echo "error: --type must be fix, feature, refactor or chore" >&2; exit 1 ;; esac
case "$SCALE_FLAG" in ""|trivial|lite|full) ;; *) echo "error: --scale must be trivial, lite or full" >&2; exit 1 ;; esac
case "$DEEP" in ""|*[!0-9]*) [ -z "$DEEP" ] || { echo "error: --deep takes a number" >&2; exit 1; } ;; esac

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PLUGIN_ROOT=$(dirname "$SCRIPT_DIR")
PROFILES="$PLUGIN_ROOT/references/profiles.md"
[ -f "$PROFILES" ] || { echo "error: profile matrix not found at $PROFILES" >&2; exit 1; }

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "error: not a git repository" >&2; exit 1; }
cd "$REPO_ROOT"

# ── Context script ────────────────────────────────────────────────────
# One wrapped call, printed verbatim: the caller gets PR metadata, branch state
# and ANCHORS without a second round trip. A failure here is not fatal — the plan
# falls back to git-only facts.
CTX=""
CTX_NOTE=""
if [ "$WANT_CONTEXT" = true ]; then
  CTX_ARGS=(--no-diff)
  [ -n "$PR" ] && CTX_ARGS+=(--pr "$PR")
  if ! CTX=$("$SCRIPT_DIR/get-pr-context.sh" "${CTX_ARGS[@]}" 2>&1); then
    CTX_NOTE="context script failed — plan uses git-only facts"
  fi
  [ -n "$CTX" ] && printf '%s\n\n' "$CTX"
fi

# Read a key from the ANCHORS section only. Everything before it can contain a PR
# body, which is user-controlled text that must never be mistaken for a SHA.
anchor() {
  printf '%s\n' "$CTX" | awk -v key="$1" '
    /^=== ANCHORS ===$/ { in_section = 1; next }
    /^=== / { in_section = 0 }
    in_section && $1 == key ":" { print $2; exit }
    in_section && index($0, key ": ") == 1 { print substr($0, length(key) + 3); exit }
  '
}

BRANCH=$(git branch --show-current 2>/dev/null || echo "")
HEAD0=$(git rev-parse HEAD 2>/dev/null || echo "")

BASE_BRANCH=$(anchor base_branch)
if [ -z "$BASE_BRANCH" ]; then
  if git rev-parse --verify origin/main >/dev/null 2>&1; then BASE_BRANCH="main"
  elif git rev-parse --verify origin/master >/dev/null 2>&1; then BASE_BRANCH="master"
  else BASE_BRANCH=""; fi
fi

ANCHOR_BASE=$(anchor merge_base)
ANCHOR_HEAD=$(anchor head)
case "$ANCHOR_BASE" in *[!0-9a-f]*) ANCHOR_BASE="" ;; esac
case "$ANCHOR_HEAD" in *[!0-9a-f]*) ANCHOR_HEAD="" ;; esac

# self mode always reviews the local branch, so its head is local HEAD; the anchors'
# base is only trusted when it was computed against that same head (an unpushed or
# rebased branch otherwise drags base-branch commits into the diff).
BASE=""
HEAD=""
BASE_SOURCE="anchors"
if [ "$MODE" = "self" ]; then
  HEAD="$HEAD0"
  if [ -n "$ANCHOR_BASE" ] && [ "$ANCHOR_HEAD" = "$HEAD0" ]; then
    BASE="$ANCHOR_BASE"
  elif [ -n "$BASE_BRANCH" ]; then
    BASE=$(git merge-base "origin/$BASE_BRANCH" HEAD 2>/dev/null || echo "")
    BASE_SOURCE="recomputed"
  fi
else
  HEAD="${ANCHOR_HEAD:-$HEAD0}"
  BASE="$ANCHOR_BASE"
  if [ -z "$BASE" ] && [ -n "$BASE_BRANCH" ]; then
    BASE=$(git merge-base "origin/$BASE_BRANCH" "$HEAD" 2>/dev/null || echo "")
    BASE_SOURCE="recomputed"
  fi
fi

# ── Guards ────────────────────────────────────────────────────────────
GUARD="ok"
if [ "$MODE" = "self" ]; then
  case "$BRANCH" in
    main|master) GUARD="refuse: on $BRANCH — self-review runs on a topic branch" ;;
    maintenance/*) GUARD="refuse: on a maintenance branch — self-review runs on a topic branch" ;;
    "") GUARD="refuse: detached HEAD — check out the branch first" ;;
  esac
  if [ "$GUARD" = "ok" ] && [ -n "$(git status --porcelain --untracked-files=no 2>/dev/null)" ]; then
    GUARD="refuse: tracked files are dirty — commit or stash first (the coverage stage restores mutants against the index)"
  fi
fi
if [ "$GUARD" = "ok" ] && [ -z "$BASE" ]; then
  GUARD="refuse: cannot resolve the merge base — fetch the base branch, or pass --pr"
fi

# ── Change type ───────────────────────────────────────────────────────
PR_TITLE=""
if command -v gh >/dev/null 2>&1; then
  GH_ARGS=()
  [ -n "$PR" ] && GH_ARGS+=("$PR")
  PR_TITLE=$(gh pr view ${GH_ARGS[@]+"${GH_ARGS[@]}"} --json title --jq .title 2>/dev/null || echo "")
fi

# Map a conventional-commit subject to a type. Only the prefix is read; the rest of
# the subject is never interpreted.
prefix_type() {
  case "$1" in
    fix:*|fix\(*) echo fix ;;
    feat:*|feat\(*) echo feature ;;
    refactor:*|refactor\(*|perf:*|perf\(*) echo refactor ;;
    test:*|test\(*|docs:*|docs\(*|chore:*|chore\(*|build:*|build\(*|deps:*|deps\(*|ci:*|ci\(*) echo chore ;;
    *) echo "" ;;
  esac
}

TYPE=""
TYPE_SIGNAL=""
if [ -n "$TYPE_FLAG" ]; then
  TYPE="$TYPE_FLAG"; TYPE_SIGNAL="--$TYPE_FLAG flag"
fi

TITLE_TYPE=$(prefix_type "$PR_TITLE")
if [ -z "$TYPE" ] && [ -n "$TITLE_TYPE" ]; then
  TYPE="$TITLE_TYPE"; TYPE_SIGNAL="PR title prefix"
fi

# Majority conventional prefix across the branch's commits.
COMMIT_TYPE=""
COMMIT_TALLY=""
if [ -n "$BASE" ]; then
  COMMIT_SUBJECTS=$(git log --format=%s "$BASE..$HEAD" 2>/dev/null || echo "")
  if [ -n "$COMMIT_SUBJECTS" ]; then
    fixes=0; feats=0; refs=0; chores=0; total=0
    while IFS= read -r subject; do
      [ -z "$subject" ] && continue
      total=$((total + 1))
      case "$(prefix_type "$subject")" in
        fix) fixes=$((fixes + 1)) ;;
        feature) feats=$((feats + 1)) ;;
        refactor) refs=$((refs + 1)) ;;
        chore) chores=$((chores + 1)) ;;
      esac
    done <<< "$COMMIT_SUBJECTS"
    best=0
    for pair in "fix:$fixes" "feature:$feats" "refactor:$refs" "chore:$chores"; do
      n="${pair#*:}"
      if [ "$n" -gt "$best" ]; then best="$n"; COMMIT_TYPE="${pair%%:*}"; fi
    done
    [ -n "$COMMIT_TYPE" ] && COMMIT_TALLY="$best/$total"
  fi
fi
if [ -z "$TYPE" ] && [ -n "$COMMIT_TYPE" ]; then
  TYPE="$COMMIT_TYPE"; TYPE_SIGNAL="commit majority ($COMMIT_TALLY)"
fi

BRANCH_TYPE=""
case "$BRANCH" in
  fix/*|bugfix/*|hotfix/*) BRANCH_TYPE=fix ;;
  feat/*|feature/*) BRANCH_TYPE=feature ;;
  refactor/*|perf/*) BRANCH_TYPE=refactor ;;
  chore/*|docs/*|test/*|ci/*|build/*|deps/*) BRANCH_TYPE=chore ;;
esac
if [ -z "$TYPE" ] && [ -n "$BRANCH_TYPE" ]; then
  TYPE="$BRANCH_TYPE"; TYPE_SIGNAL="branch name prefix"
fi

if [ -z "$TYPE" ]; then
  TYPE="undetermined"
  TYPE_SIGNAL="none resolved — decide from the diff shape (see references/pipeline.md)"
fi

# A lower signal that is *more demanding* than the winner is handed to the code
# pass as a question; it never silently upgrades the type.
demand() { case "$1" in feature) echo 3 ;; fix) echo 2 ;; refactor) echo 1 ;; chore) echo 0 ;; *) echo -1 ;; esac; }
TYPE_CONFLICT="none"
if [ "$TYPE" != "undetermined" ]; then
  win=$(demand "$TYPE")
  for cand in "PR title:$TITLE_TYPE" "commits:$COMMIT_TYPE" "branch name:$BRANCH_TYPE"; do
    other="${cand#*:}"
    [ -z "$other" ] && continue
    [ "$other" = "$TYPE" ] && continue
    if [ "$(demand "$other")" -gt "$win" ]; then
      TYPE_CONFLICT="${cand%%:*} → $other (more demanding than the declared type — hand it to the code pass)"
      win=$(demand "$other")
    fi
  done
fi

# ── Scale ─────────────────────────────────────────────────────────────
LINES=0
FILES=0
CHANGED=""
if [ -n "$BASE" ]; then
  CHANGED=$(git diff --name-only --no-renames "$BASE..$HEAD" 2>/dev/null || echo "")
  read -r LINES FILES <<< "$(git diff --numstat -M "$BASE..$HEAD" 2>/dev/null | awk -F'\t' '
    {
      p = $3
      if (p ~ /\.lock$/ || p ~ /(^|\/)package-lock\.json$/) next
      if (p ~ /(^|\/)(dist|node_modules|__snapshots__)\//) next
      if (p ~ /\.(png|jpg|jpeg|gif|webp|ico)$/) next
      files++
      if ($1 == "-" || $2 == "-") next
      lines += $1 + $2
    }
    END { printf "%d %d\n", lines + 0, files + 0 }')"
fi

SCALE=""
if [ "$LINES" -le 10 ] && [ "$FILES" -le 2 ]; then SCALE="trivial"
elif [ "$LINES" -le 100 ] && [ "$FILES" -le 6 ]; then SCALE="lite"
else SCALE="full"; fi
SCALE_REASON="size"

# Risk overrides — size is a proxy for risk, not risk itself.
OVERRIDES=""
add_override() { OVERRIDES="${OVERRIDES:+$OVERRIDES, }$1"; }
if [ -n "$CHANGED" ]; then
  printf '%s\n' "$CHANGED" | grep -q '\.d\.ts$' && add_override "a .d.ts file changed"
  printf '%s\n' "$CHANGED" | grep -qE '^(\.github/|\.circleci/|Jenkinsfile|azure-pipelines|\.gitlab-ci)' && add_override "CI or build infra touched"
  printf '%s\n' "$CHANGED" | grep -qiE '(^|/)(release|publish)[^/]*\.(sh|js|mjs|yml|yaml)$' && add_override "release tooling touched"
fi
if [ -n "$BASE" ] && git diff --unified=0 "$BASE..$HEAD" 2>/dev/null | grep -qE '^\+[[:space:]]*export '; then
  add_override "a new export added"
fi
[ -n "$DEEP" ] && add_override "--deep passed"

if [ -n "$OVERRIDES" ] && [ "$SCALE" != "full" ]; then
  SCALE="full"; SCALE_REASON="risk override: $OVERRIDES"
elif [ -n "$OVERRIDES" ]; then
  SCALE_REASON="size (risk override also applies: $OVERRIDES)"
fi
if [ -n "$SCALE_FLAG" ]; then
  SCALE="$SCALE_FLAG"; SCALE_REASON="forced by --scale"
fi

# ── Resolve the matrix row ────────────────────────────────────────────
matrix_row() {
  awk -F'|' -v mode="$1" -v type="$2" -v scale="$3" '
    /^## Matrix/ { in_matrix = 1; next }
    /^## / { in_matrix = 0 }
    !in_matrix || NF < 6 { next }
    {
      for (i = 2; i <= 6; i++) { gsub(/^[ \t]+|[ \t]+$/, "", $i) }
      if ($2 == "mode" || $2 ~ /^-+$/) next
      if ($2 == mode && $3 == type && ($4 == scale || $4 == "any")) { print $5 "\t" $6; exit }
    }
  ' "$PROFILES"
}

pass_agent() {
  awk -F'|' -v id="$1" '
    /^## Passes/ { in_passes = 1; next }
    /^## / { in_passes = 0 }
    !in_passes || NF < 6 { next }
    {
      for (i = 2; i <= 5; i++) { gsub(/^[ \t]+|[ \t]+$/, "", $i) }
      if ($2 == id) { print $3 "\t" $4 "\t" $5; exit }
    }
  ' "$PROFILES"
}

# `undetermined` is a matrix row in pr mode (the base passes still apply) but not in self
# mode, where the type picks the whole profile: the caller resolves it from the diff shape
# and re-runs with --type rather than getting a silently chosen profile.
LOOKUP_TYPE="$TYPE"

ROW=""
[ "$MODE" != "arch" ] && ROW=$(matrix_row "$MODE" "$LOOKUP_TYPE" "$SCALE")
PASS_TOKENS=""
MUTANTS=0
if [ -n "$ROW" ]; then
  PASS_TOKENS=$(printf '%s' "$ROW" | cut -f1)
  MUTANTS=$(printf '%s' "$ROW" | cut -f2)
fi

# Effective mutant budget: the row's number, capped by the scale tier.
case "$MUTANTS" in ''|*[!0-9]*) MUTANTS=0 ;; esac
case "$SCALE" in trivial) CAP=3 ;; lite) CAP=8 ;; *) CAP=999 ;; esac
[ "$MUTANTS" -gt "$CAP" ] && MUTANTS="$CAP"
[ "$COVERAGE" = "off" ] && MUTANTS=0
[ "$MODE" != "self" ] && MUTANTS=0

# ── Conventions doc (named in the plan, quoted into the context) ──────
CONVENTIONS=""
for f in .github/review-instructions.md .github/copilot-instructions.md CONVENTIONS.md CLAUDE.md AGENTS.md; do
  if [ -f "$f" ]; then CONVENTIONS="$f"; break; fi
done

# ── Report paths ──────────────────────────────────────────────────────
SLUG=$(printf '%s' "${BRANCH:-detached}" | tr '/' '-')
if [ -z "$REPORT_DIR" ]; then
  case "$MODE" in
    self) REPORT_DIR=".omc/self-review" ;;
    pr) REPORT_DIR=".omc/pr-review" ;;
    arch) REPORT_DIR="" ;;
  esac
  if [ -n "$REPORT_DIR" ] && ! git check-ignore -q "${REPORT_DIR%%/*}" 2>/dev/null; then
    REPORT_DIR="SCRATCHPAD"
  fi
fi

# ── Command map ───────────────────────────────────────────────────────
LINT_CMD=""; TEST_CMD=""; SRC_GLOB=""; CMD_SOURCE=""
if [ -d packages ] && ls packages/*/src >/dev/null 2>&1; then
  LINT_CMD="yarn lint"; TEST_CMD="yarn test --group <package>"; SRC_GLOB="packages/*/src/*.js"
  CMD_SOURCE="monorepo layout (packages/*/src)"
elif [ -f package.json ]; then
  grep -q '"lint"' package.json && LINT_CMD="yarn lint"
  grep -q '"test"' package.json && TEST_CMD="yarn test"
  SRC_GLOB="src/**"
  CMD_SOURCE="package.json scripts — confirm against CLAUDE.md / AGENTS.md"
else
  CMD_SOURCE="unknown — take lint/test commands from CLAUDE.md / AGENTS.md"
fi

AFFECTED=""
if [ -n "$CHANGED" ]; then
  AFFECTED=$(printf '%s\n' "$CHANGED" | awk -F/ '$1 == "packages" && NF > 2 { print $1 "/" $2 }' | sort -u | tr '\n' ' ')
fi

# ── File lanes ────────────────────────────────────────────────────────
# The prepared patches are split so a pass reads only its own material: the
# test diff is most of a branch's line count, and every pass that does not
# review tests was paying for it. See references/profiles.md's `reads` column.
TEST_RE='(^|/)(test|tests|__tests__|it)/|\.(test|spec)\.[cm]?[jt]sx?$|Test\.java$|IT\.java$|Tests?\.kt$'
TEST_FILES=""
PROD_FILES=""
if [ -n "$CHANGED" ]; then
  TEST_FILES=$(printf '%s\n' "$CHANGED" | grep -E "$TEST_RE" | tr '\n' ' ' || true)
  PROD_FILES=$(printf '%s\n' "$CHANGED" | grep -vE "$TEST_RE" | tr '\n' ' ' || true)
fi

# Files with a comment inside or beside a hunk — the code pass's extra input for
# its Comments category, which has two questions: comments the diff ADDS (policy)
# and comments the diff left stale (rot). The first needs added comment lines; the
# second needs comments near changed code, so the window is -U3 and removed/context
# lines count too. A file with no comment within three lines of a change cannot
# hold either finding.
COMMENT_FILES=""
if [ -n "$BASE" ]; then
  COMMENT_FILES=$(git diff -U3 "$BASE..$HEAD" 2>/dev/null | awk '
    /^diff --git |^index |^--- |^\+\+\+ |^@@ |^(new|deleted) file|^similarity|^rename / {
      if ($0 ~ /^\+\+\+ b\//) { file = substr($0, 7) }
      next
    }
    file == "" { next }
    {
      body = substr($0, 2)
      if (body ~ /(\/\/|\/\*|\*\/|<!--)/ || body ~ /^[ \t]*\*[ \t]/) {
        if (!(file in seen)) { seen[file] = 1; printf "%s ", file }
      }
    }
  ' || true)
fi

# ── Print the plan ────────────────────────────────────────────────────
echo "=== PLAN ==="
echo "mode: $MODE"
echo "guard: $GUARD"
[ -n "$CTX_NOTE" ] && echo "note: $CTX_NOTE"
echo "branch: ${BRANCH:-(detached)}"
echo "head0: $HEAD0"
echo "base: ${BASE:-unresolved}"
echo "head: ${HEAD:-unresolved}"
echo "base_branch: ${BASE_BRANCH:-unknown} (base from: $BASE_SOURCE)"
echo "pr: ${PR:-none}"
echo "type: $TYPE"
echo "type_signal: $TYPE_SIGNAL"
echo "type_conflict: $TYPE_CONFLICT"
echo "scale: $SCALE"
echo "scale_counts: $LINES lines, $FILES files (lock, generated, snapshot and image files excluded)"
echo "scale_reason: $SCALE_REASON"
echo "deep: ${DEEP:-none}"
echo "coverage: $COVERAGE"
echo "mutants: $MUTANTS"
echo "conventions_doc: ${CONVENTIONS:-none}"

if [ "$GUARD" != "ok" ]; then
  echo "passes: none — the guard refused this run"
  exit 2
fi

if [ "$MODE" = "arch" ]; then
  echo "passes: none — arch mode runs the lens trio per skills/arch-review/SKILL.md"
elif [ "$LOOKUP_TYPE" = "undetermined" ]; then
  echo "passes: none — resolve the type from the diff shape (references/pipeline.md step 1) and re-run with --type"
elif [ -z "$PASS_TOKENS" ]; then
  echo "passes: none — no matrix row for $MODE/$LOOKUP_TYPE/$SCALE (check references/profiles.md)"
else
  echo "passes:"
  COUNT=0
  for token in $PASS_TOKENS; do
    INFO=$(pass_agent "$token")
    AGENT=$(printf '%s' "$INFO" | cut -f1)
    READS=$(printf '%s' "$INFO" | cut -f2)
    ADDS=$(printf '%s' "$INFO" | cut -f3)
    [ -z "$AGENT" ] && AGENT="(no agent in references/profiles.md for '$token')"
    COUNT=$((COUNT + 1))
    printf '  %-7s %-28s reads: %-14s prompt adds: %s\n' \
      "$token" "$AGENT" "${READS:-both}" "${ADDS:--}"
  done
  echo "agents: $COUNT"
fi

echo "prod_files: ${PROD_FILES:-none}"
echo "test_files: ${TEST_FILES:-none}"
echo "comment_files: ${COMMENT_FILES:-none}"

if [ -n "$REPORT_DIR" ]; then
  echo "report_dir: $REPORT_DIR"
  echo "report: $REPORT_DIR/$SLUG-FINDINGS.md"
  echo "context: $REPORT_DIR/context.md"
  echo "patch_prod: $REPORT_DIR/prod.patch"
  echo "patch_tests: $REPORT_DIR/tests.patch"
fi
echo "commands: lint=${LINT_CMD:-unknown} test=${TEST_CMD:-unknown} src_glob=${SRC_GLOB:-unknown} (source: $CMD_SOURCE)"
echo "affected_packages: ${AFFECTED:-none}"
echo "risk_check_manual: a deleted or weakened assertion in an existing test also forces the full tier — this script cannot detect it, so check the test hunks yourself"
