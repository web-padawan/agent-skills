#!/usr/bin/env bash
# review-plan.sh — compute the review plan for a review skill: the anchors, the
# change type, the scale tier, the pass list with its agents and read lanes, the
# mutant and deep-block budgets, the guards, and the report paths.
#
# The matrix it resolves lives in references/profiles.md — this script parses that
# file, so the tables are never restated in a skill.
#
# Usage:
#   review-plan.sh [--mode self|pr] [--pr <number-or-url>]
#                  [--type fix|feature|refactor|chore] [--scale trivial|lite|full]
#                  [--deep N] [--no-coverage] [--report-dir <path>] [--no-context]
#                  [--context-out <path>] [--no-write]
#
# Prints get-pr-context.sh's sections (skip with --no-context) then === PLAN ===, and
# writes the shared context skeleton the passes read (references/pipeline.md §2) at the
# plan's `context:` path — `--context-out` picks the path, `--no-write` skips it. The
# skeleton and, for a large diff, the two patch files beside it are the only files this
# script creates; it names (never writes) the `notes:` file the orchestrator adds beside
# them. After the plan it prints `=== PROMPTS ===`: the literal prompt for each pass, with
# the pass's agent and model, so a launch copies a block instead of assembling one.
# It never stages, commits, or touches tracked files.
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
CONTEXT_OUT=""
NO_WRITE=false

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
    --context-out) CONTEXT_OUT="${2:?--context-out requires a value}"; shift 2 ;;
    --no-write) NO_WRITE=true; shift ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

case "$MODE" in self|pr) ;; *) echo "error: --mode must be self or pr" >&2; exit 1 ;; esac
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

# One-line digest of what CI already proved, read from the context script's own
# CI_STATUS section. Display only: check names come from the head's workflow files,
# so they are never parsed for anything that reaches git.
ci_summary() {
  printf '%s\n' "$CTX" | awk '
    /^=== CI_STATUS ===$/ { in_section = 1; next }
    /^=== / { in_section = 0 }
    in_section && index($0, "summary: ") == 1 { print substr($0, 10); exit }
    in_section && index($0, "unavailable: ") == 1 { print "unavailable — " substr($0, 14); exit }
  '
}

# Image baselines are the only machine-readable evidence a binary diff carries.
# stdin: PNG bytes. stdout: WxH, or nothing when the stream is not a PNG.
png_dims() {
  od -An -tu1 -N24 2>/dev/null | awk '
    { for (i = 1; i <= NF; i++) b[++n] = $i }
    END {
      if (n < 24) exit
      if (b[1] != 137 || b[2] != 80 || b[3] != 78 || b[4] != 71) exit
      printf "%dx%d", b[17]*16777216 + b[18]*65536 + b[19]*256 + b[20], \
                      b[21]*16777216 + b[22]*65536 + b[23]*256 + b[24]
    }'
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

# A lower signal that is *more demanding* than the winner is handed to the change
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
      TYPE_CONFLICT="${cand%%:*} → $other (more demanding than the declared type — hand it to the change pass)"
      win=$(demand "$other")
    fi
  done
fi

# ── File lanes ────────────────────────────────────────────────────────
# The prepared diff is split so a pass reads only its own material: the test diff
# is most of a branch's line count, and every pass that does not review tests was
# paying for it. See references/profiles.md's `reads` column.
TEST_RE='(^|/)(test|tests|__tests__|it)/|\.(test|spec)\.[cm]?[jt]sx?$|Test\.java$|IT\.java$|Tests?\.kt$'
CHANGED=""
TEST_FILES=""
PROD_FILES=""
BINARY_FILES=""
if [ -n "$BASE" ]; then
  CHANGED=$(git diff --name-only --no-renames "$BASE..$HEAD" 2>/dev/null || echo "")
fi
if [ -n "$CHANGED" ]; then
  # Binaries get their own lane: named, not diffed (a patch would only hold a
  # `Bin N -> M bytes` stub), and never dropped — screenshot baselines are evidence.
  BINARY_FILES=$(git diff --numstat "$BASE..$HEAD" 2>/dev/null | awk -F'\t' '$1 == "-" && $2 == "-" { print $3 }' | tr '\n' ' ' || true)
  TEXT_CHANGED="$CHANGED"
  if [ -n "$BINARY_FILES" ]; then
    for bin in $BINARY_FILES; do
      TEXT_CHANGED=$(printf '%s\n' "$TEXT_CHANGED" | grep -vxF "$bin" || true)
    done
  fi
  TEST_FILES=$(printf '%s\n' "$TEXT_CHANGED" | grep -E "$TEST_RE" | tr '\n' ' ' || true)
  PROD_FILES=$(printf '%s\n' "$TEXT_CHANGED" | grep -vE "$TEST_RE" | tr '\n' ' ' || true)
fi

# ── Scale ─────────────────────────────────────────────────────────────
# Sized by PRODUCTION lines: tests never enter the mutant or deep budgets, and a
# 30-line fix with 80 lines of tests is a lite review, not a full one.
LINES=0
TOTAL_LINES=0
FILES=0
if [ -n "$BASE" ]; then
  read -r LINES TOTAL_LINES FILES <<< "$(git diff --numstat -M "$BASE..$HEAD" 2>/dev/null | awk -F'\t' -v test_re="$TEST_RE" '
    {
      p = $3
      if (p ~ /\.lock$/ || p ~ /(^|\/)package-lock\.json$/) next
      if (p ~ /(^|\/)(dist|node_modules|__snapshots__)\//) next
      if (p ~ /\.(png|jpg|jpeg|gif|webp|ico)$/) next
      files++
      if ($1 == "-" || $2 == "-") next
      total += $1 + $2
      if (p ~ test_re) next
      prod += $1 + $2
    }
    END { printf "%d %d %d\n", prod + 0, total + 0, files + 0 }')"
fi

SCALE=""
if [ "$LINES" -le 10 ] && [ "$FILES" -le 2 ]; then SCALE="trivial"
elif [ "$LINES" -le 150 ] && [ "$FILES" -le 8 ]; then SCALE="lite"
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
    !in_matrix || NF < 7 { next }
    {
      for (i = 2; i <= 7; i++) { gsub(/^[ \t]+|[ \t]+$/, "", $i) }
      if ($2 == "mode" || $2 ~ /^-+$/) next
      if ($2 == mode && $3 == type && ($4 == scale || $4 == "any")) { print $5 "\t" $6 "\t" $7; exit }
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

# Model per pass by scale — references/profiles.md, "Pass model". The header row names
# the pass columns, so a new pass is a new column, not a script change.
pass_model() {  # pass_model <scale> <id>
  awk -F'|' -v scale="$1" -v id="$2" '
    /^## Pass model/ { in_tbl = 1; next }
    /^## / { in_tbl = 0 }
    !in_tbl || NF < 4 { next }
    {
      for (i = 2; i < NF; i++) { gsub(/^[ \t]+|[ \t]+$/, "", $i) }
      if ($2 == "scale") { for (i = 3; i < NF; i++) if ($i == id) col = i; next }
      if ($2 ~ /^-+$/) next
      if ($2 == scale && col) { print $col; exit }
    }
  ' "$PROFILES"
}

# `undetermined` is a matrix row in pr mode (the base passes still apply) but not in self
# mode, where the type picks the whole profile: the caller resolves it from the diff shape
# and re-runs with --type rather than getting a silently chosen profile.
LOOKUP_TYPE="$TYPE"

ROW=$(matrix_row "$MODE" "$LOOKUP_TYPE" "$SCALE")
PASS_TOKENS=""
MUTANTS=0
DEEP_ROW=0
if [ -n "$ROW" ]; then
  PASS_TOKENS=$(printf '%s' "$ROW" | cut -f1)
  MUTANTS=$(printf '%s' "$ROW" | cut -f2)
  DEEP_ROW=$(printf '%s' "$ROW" | cut -f3)
fi

# Effective mutant budget: the row's number, capped by the scale tier.
case "$MUTANTS" in ''|*[!0-9]*) MUTANTS=0 ;; esac
case "$SCALE" in trivial) CAP=3 ;; lite) CAP=8 ;; *) CAP=999 ;; esac
[ "$MUTANTS" -gt "$CAP" ] && MUTANTS="$CAP"
[ "$COVERAGE" = "off" ] && MUTANTS=0
[ "$MODE" != "self" ] && MUTANTS=0

# Effective deep-block budget for the change pass: the row's number, capped by the
# scale tier; --deep N overrides outright (0 keeps the pass, skips its blocks).
case "$DEEP_ROW" in ''|*[!0-9]*) DEEP_ROW=0 ;; esac
case "$SCALE" in trivial) DCAP=1 ;; lite) DCAP=2 ;; *) DCAP=999 ;; esac
[ "$DEEP_ROW" -gt "$DCAP" ] && DEEP_ROW="$DCAP"
DEEP_SOURCE="matrix, capped by scale"

# Deep candidates — what the diff actually offers a boundary block: `.d.ts` files,
# new exports, added public (non-underscore) methods at class indentation. A fix with
# none of these gets one block for its top change instead of three surveys. Public
# properties are not counted directly; the repo convention that syncs them into the
# `.d.ts` catches them through the first signal.
CAND_DTS=0; CAND_EXPORTS=0; CAND_METHODS=0
if [ -n "$BASE" ] && [ -n "$PROD_FILES" ]; then
  CAND_DTS=$(printf '%s\n' $PROD_FILES | grep -c '\.d\.ts$' || true)
  CAND_EXPORTS=$(git diff --unified=0 "$BASE..$HEAD" -- $PROD_FILES 2>/dev/null | grep -cE '^\+[[:space:]]*export ' || true)
  CAND_METHODS=$(git diff --unified=0 "$BASE..$HEAD" -- $PROD_FILES 2>/dev/null | awk '
    /^\+\+\+ b\// { file = substr($0, 7); next }
    /^\+/ {
      if (file !~ /\.[cm]?[jt]sx?$/ || file ~ /\.d\.ts$/) next
      body = substr($0, 2)
      if (body !~ /^    (static |async |get |set )?[A-Za-z$][A-Za-z0-9$]*[ \t]*\(/) next
      name = body; sub(/^    (static |async |get |set )?/, "", name); sub(/[ \t]*\(.*$/, "", name)
      if (name ~ /^(if|for|while|switch|catch|return|super|constructor|ready|render|connectedCallback|disconnectedCallback|attributeChangedCallback|firstUpdated|willUpdate|updated|requestUpdate|performUpdate)$/) next
      n++
    }
    END { print n + 0 }' || echo 0)
fi
DEEP_CANDIDATES=$((CAND_DTS + CAND_EXPORTS + CAND_METHODS))
if [ "$DEEP_ROW" -gt 0 ]; then
  CAND_CAP=$DEEP_CANDIDATES; [ "$CAND_CAP" -lt 1 ] && CAND_CAP=1
  if [ "$DEEP_ROW" -gt "$CAND_CAP" ]; then DEEP_ROW="$CAND_CAP"; DEEP_SOURCE="matrix, capped by scale and by $DEEP_CANDIDATES deep candidates"; fi
fi
if [ -n "$DEEP" ]; then DEEP_ROW="$DEEP"; DEEP_SOURCE="--deep flag"; fi

# Per-pass effort ceiling from the scale tier — references/profiles.md, "Pass effort".
case "$SCALE" in
  trivial) EFFORT=10 ;;
  lite) EFFORT=20 ;;
  *) EFFORT=30 ;;
esac

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
    # pr mode never writes into the repo: the review record is the reviewer's own,
    # never committed or posted (skills/pr-review/SKILL.md step 4).
    pr) REPORT_DIR="SCRATCHPAD" ;;
  esac
  if [ -n "$REPORT_DIR" ] && [ "$REPORT_DIR" != "SCRATCHPAD" ] \
     && ! git check-ignore -q "${REPORT_DIR%%/*}" 2>/dev/null; then
    REPORT_DIR="SCRATCHPAD"
  fi
fi

# ── Command map ───────────────────────────────────────────────────────
LINT_CMD=""; TEST_CMD=""; SRC_GLOB=""; CMD_SOURCE=""
if [ -d packages ] && ls packages/*/src >/dev/null 2>&1; then
  LINT_CMD="yarn lint"; TEST_CMD="yarn test --group <package>"; SRC_GLOB="packages/*/src/**/*.{js,ts}"
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

# Dimensions for every changed PNG. A changed WxH is a layout change and belongs
# in the context file as a Settled fact; an unchanged WxH with moved bytes is a
# repaint. Without this, passes are left guessing a baseline from its byte count.
BINARY_DIMS=""
if [ -n "$BINARY_FILES" ] && [ -n "$BASE" ]; then
  for bin in $BINARY_FILES; do
    case "$bin" in *.png|*.PNG) ;; *) continue ;; esac
    BIN_BEFORE=$(git show "$BASE:$bin" 2>/dev/null | png_dims || true)
    BIN_AFTER=$(git show "$HEAD:$bin" 2>/dev/null | png_dims || true)
    [ -z "$BIN_BEFORE" ] && BIN_BEFORE="absent"
    [ -z "$BIN_AFTER" ] && BIN_AFTER="absent"
    if [ "$BIN_BEFORE" = "$BIN_AFTER" ]; then
      BINARY_DIMS="${BINARY_DIMS}  $bin: $BIN_AFTER (size unchanged)
"
    else
      BINARY_DIMS="${BINARY_DIMS}  $bin: $BIN_BEFORE -> $BIN_AFTER
"
    fi
  done
fi

# Mutant candidate pool — advisory, not a budget: non-styling source lines the
# coverage stage could mutate (mutation.md skips styling), so a styling-only diff
# reports 0 instead of sending the stage looking for work that does not exist.
MUTANT_POOL=0
if [ -n "$PROD_FILES" ] && [ -n "$BASE" ]; then
  MUTANT_POOL=$(git diff --unified=0 "$BASE..$HEAD" -- $PROD_FILES 2>/dev/null | awk '
    /^\+\+\+ b\// { file = substr($0, 7); next }
    /^\+/ {
      if (file !~ /\.[cm]?[jt]sx?$/) next          # source code only
      if (file ~ /(^|\/)styles\// || file ~ /-styles\.[cm]?[jt]s$/) next   # styling by construction
      body = substr($0, 2)
      sub(/^[ \t]+/, "", body)
      if (body == "") next
      if (body ~ /^(import|export[ \t]+\{|export[ \t]+\*)/) next
      if (body ~ /^(\/\/|\/\*|\*|\*\/)/) next
      if (body ~ /^[)}\]`;,]+$/) next
      if (body ~ /^-{0,2}[_a-z][-_a-z0-9]*:[ \t]/) next   # CSS declaration, custom properties included
      if (body ~ /^[.:&#@[$]/ || body ~ /^[a-z-]+[ \t]*\{$/) next   # CSS selector, at-rule, interpolated selector
      if (body ~ /^(var|color-mix|calc|light-dark|oklch|linear-gradient)\(/) next   # wrapped CSS value
      n++
    }
    END { print n + 0 }' || echo 0)
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

# The branch's own commit sequence. `base..head` flattens it, but the ORDER is
# evidence: a fix commit landing after the commit that captured a baseline, or
# after the test that was supposed to pin it, is exactly the stale-baseline and
# untested-fix smell — and it is invisible in the squashed diff.
BRANCH_COMMITS=""
if [ -n "$BASE" ]; then
  BRANCH_COMMITS=$(git log --oneline --no-decorate --reverse "$BASE..$HEAD" 2>/dev/null || true)
fi

# ── Context skeleton ──────────────────────────────────────────────────
# Everything deterministic about the shared context file (references/pipeline.md §2):
# the framing, identity, rules and rubric copied from the reference docs by marker,
# the PR body, the lanes, the diff (inline when small), the conventions chapters the
# touched file kinds select, and the Settled facts this script can prove. The
# orchestrator appends only what it verified itself.
block() {  # block <doc> <name> — print one marked block from a reference doc, headings demoted
  awk -v name="$2" '
    index($0, "<!-- block:" name " -->") == 1 { f = 1; next }
    /^<!-- \/block -->/ { f = 0 }
    f' "$1" | sed 's/^#/##/'
}

conventions_excerpt() {  # conventions_excerpt <doc> "<signals>" — chapters selected by signal
  local doc="$1" signals="$2" nhead re=""
  nhead=$(grep -c '^## ' "$doc" 2>/dev/null || true)
  if [ "${nhead:-0}" -lt 3 ]; then
    if [ "$(wc -l < "$doc")" -le 200 ]; then sed 's/^#/##/' "$doc"
    else echo "(the conventions doc has no chapters and is over 200 lines — not quoted; open \`$doc\` only for a finding that needs it)"; fi
    return
  fi
  for sig in $signals; do
    case "$sig" in
      src) re="${re}|component|implement|code style|naming" ;;
      properties) re="${re}|propert|attribute" ;;
      events) re="${re}|event" ;;
      lifecycle) re="${re}|lifecycle|template|render" ;;
      a11y) re="${re}|accessib|a11y" ;;
      deprecation) re="${re}|deprecat" ;;
      jsdoc) re="${re}|jsdoc|documenting|documentation" ;;
      types) re="${re}|typescript|type definition" ;;
      css) re="${re}|styl|them|css" ;;
      test) re="${re}|test" ;;
    esac
  done
  re="${re#|}"
  if [ -z "$re" ]; then
    echo "(no conventions chapter selected — the diff touches no source, style or test file)"
    return
  fi
  # Chapter headings become H3 so the skeleton keeps its own H2 structure.
  awk -v re="$re" '
    /^## / { keep = (tolower($0) ~ re) }
    /^# / { next }
    keep' "$doc" | sed 's/^#/##/'
}

# Signals for the conventions excerpt: the kinds of file touched, plus what the added
# production lines actually use — a diff that adds no event needs no Events chapter.
conventions_signals() {
  local sig="" added=""
  for f in $PROD_FILES; do
    case "$f" in
      *.d.ts) sig="$sig types" ;;
      *.css|*styles/*|*-styles.js|*-styles.ts) sig="$sig css" ;;
      *.js|*.mjs|*.cjs|*.ts|*.mts|*.cts|*.jsx|*.tsx|*.java|*.kt) sig="$sig src" ;;
    esac
  done
  if [ -n "$PROD_FILES" ]; then
    added=$(git diff --unified=0 "$BASE..$HEAD" -- $PROD_FILES 2>/dev/null | grep '^+' | grep -v '^+++' || true)
    printf '%s\n' "$added" | grep -qE 'static get properties|reflectToAttribute|notify:|@attr|@property' && sig="$sig properties"
    printf '%s\n' "$added" | grep -qE 'dispatchEvent|CustomEvent|@fires|addEventListener' && sig="$sig events"
    printf '%s\n' "$added" | grep -qE 'connectedCallback|disconnectedCallback|firstUpdated|willUpdate|updated\(|render\(|ready\(|static get observers' && sig="$sig lifecycle"
    printf '%s\n' "$added" | grep -qE 'role=|aria-|tabindex|focusVisible|announce\(' && sig="$sig a11y"
    printf '%s\n' "$added" | grep -qE '@deprecated|issueWarning' && sig="$sig deprecation"
    printf '%s\n' "$added" | grep -qE '^\+[[:space:]]*(/\*\*|\*[[:space:]]|\* @)' && sig="$sig jsdoc types"
  fi
  [ -n "$TEST_FILES" ] && sig="$sig test"
  printf '%s\n' $sig | awk 'NF && !seen[$0]++' | tr '\n' ' '
}

CONTEXT_PATH=""
CONTEXT_NOTE=""
if [ -n "$CONTEXT_OUT" ]; then CONTEXT_PATH="$CONTEXT_OUT"
elif [ -n "$REPORT_DIR" ] && [ "$REPORT_DIR" != "SCRATCHPAD" ]; then CONTEXT_PATH="$REPORT_DIR/context.md"
else CONTEXT_NOTE="not written — no git-ignored report dir to hold it; pass --context-out <path>"
fi
[ "$NO_WRITE" = true ] && { CONTEXT_PATH=""; CONTEXT_NOTE="not written (--no-write)"; }
[ "$GUARD" != "ok" ] && { CONTEXT_PATH=""; CONTEXT_NOTE="not written — the guard refused this run"; }
[ -z "$BASE" ] || [ -z "$HEAD" ] && { CONTEXT_PATH=""; CONTEXT_NOTE="not written — anchors unresolved"; }

# The orchestrator's own additions go in a sibling file it creates with Write. Editing the
# skeleton would need a Read first, and that Read pulls the inline diff through the
# orchestrator's context — the one cost the skeleton exists to remove.
NOTES_PATH=""
[ -n "$CONTEXT_PATH" ] && NOTES_PATH="${CONTEXT_PATH%.md}-notes.md"

PROD_DIFF_WHERE="none"
TESTS_DIFF_WHERE="none"
CONTEXT_LINES=0
if [ -n "$CONTEXT_PATH" ]; then
  PATCH_STEM="${CONTEXT_PATH%.md}"
  PROD_PATCH="$PATCH_STEM-prod.patch"
  TESTS_PATCH="$PATCH_STEM-tests.patch"
  mkdir -p "$(dirname "$CONTEXT_PATH")"

  # PR fields for the identity section and the body. gh's own --jq, never grep on JSON.
  PR_NUMBER=""; PR_URL=""; PR_AUTHOR=""; PR_HEADREF=""; PR_BASEREF=""; PR_DRAFT=""; PR_BODY=""
  if command -v gh >/dev/null 2>&1; then
    PR_TSV=$(gh pr view ${GH_ARGS[@]+"${GH_ARGS[@]}"} --json number,url,author,headRefName,baseRefName,isDraft \
      --jq '[.number, .url, .author.login, .headRefName, .baseRefName, (.isDraft|tostring)] | @tsv' 2>/dev/null || true)
    if [ -n "$PR_TSV" ]; then
      IFS=$'\t' read -r PR_NUMBER PR_URL PR_AUTHOR PR_HEADREF PR_BASEREF PR_DRAFT <<< "$PR_TSV"
      PR_BODY=$(gh pr view ${GH_ARGS[@]+"${GH_ARGS[@]}"} --json body --jq .body 2>/dev/null || true)
    fi
  fi

  CHECKED_OUT="no"; [ "$HEAD0" = "$HEAD" ] && CHECKED_OUT="yes"

  SIGNALS=$(conventions_signals)

  # Prod diff: inline at -U10 up to ~400 lines — every pass reads it, so a patch file
  # only adds a Read per pass. A small file touched in several places is quoted whole
  # (numbered head) with a -U0 marker diff instead of its hunks — one cached copy beats
  # three passes each pulling the file.
  PROD_INLINE=""
  if [ -n "$PROD_FILES" ]; then
    PROD_DIFF=$(git diff -U10 "$BASE..$HEAD" -- $PROD_FILES 2>/dev/null || true)
    PROD_N=$(printf '%s\n' "$PROD_DIFF" | wc -l | tr -d ' ')
    if [ "$PROD_N" -le 400 ]; then
      FULL_FILES=""; REST_FILES=""; FULL_N=0
      for f in $PROD_FILES; do
        hunks=$(git diff -U0 "$BASE..$HEAD" -- "$f" 2>/dev/null | grep -c '^@@' || true)
        head_n=$(git show "$HEAD:$f" 2>/dev/null | wc -l | tr -d ' ' || echo 0)
        if [ "${hunks:-0}" -ge 3 ] && [ "${head_n:-0}" -gt 0 ] && [ "$head_n" -le 350 ]; then
          FULL_FILES="$FULL_FILES $f"; FULL_N=$((FULL_N + head_n))
        else
          REST_FILES="$REST_FILES $f"
        fi
      done
      if [ $((PROD_N + FULL_N)) -gt 700 ]; then FULL_FILES=""; REST_FILES="$PROD_FILES"; fi
      PROD_INLINE=$( {
        for f in $FULL_FILES; do
          echo "### Full file (head): $f"
          echo
          echo "Numbered post-change file — do not \`git show\` it again. The marker diff below names the changed lines."
          echo
          echo '```'
          git show "$HEAD:$f" | cat -n
          echo '```'
          echo
          echo "### Changed lines: $f"
          echo
          echo '```diff'
          git diff -U0 "$BASE..$HEAD" -- "$f"
          echo '```'
          echo
        done
        if [ -n "$REST_FILES" ]; then
          echo "### Hunks (-U10)"
          echo
          echo '```diff'
          git diff -U10 "$BASE..$HEAD" -- $REST_FILES
          echo '```'
        fi
      } )
      PROD_DIFF_WHERE="inline"
    else
      U=10; [ "$PROD_N" -gt 1500 ] && U=3
      git diff -U$U "$BASE..$HEAD" -- $PROD_FILES > "$PROD_PATCH" 2>/dev/null || true
      PROD_DIFF_WHERE="$PROD_PATCH"
    fi
  fi

  # Test diff: -U15 so the enclosing describe/beforeEach setup is usually in view.
  # Only the tests pass reads this lane, so it is inlined only while small — the
  # other two passes pay for every inline line without needing it.
  TESTS_INLINE=""
  if [ -n "$TEST_FILES" ]; then
    TESTS_DIFF=$(git diff -U15 "$BASE..$HEAD" -- $TEST_FILES 2>/dev/null || true)
    TESTS_N=$(printf '%s\n' "$TESTS_DIFF" | wc -l | tr -d ' ')
    if [ "$TESTS_N" -le 120 ]; then
      TESTS_INLINE="$TESTS_DIFF"; TESTS_DIFF_WHERE="inline"
    else
      printf '%s\n' "$TESTS_DIFF" > "$TESTS_PATCH"; TESTS_DIFF_WHERE="$TESTS_PATCH"
    fi
  fi

  CI_SECTION=$(printf '%s\n' "$CTX" | awk '/^=== CI_STATUS ===$/ { f = 1; next } /^=== / { f = 0 } f' | sed '/^$/d')
  COMMENTS_SECTION=$(printf '%s\n' "$CTX" | awk '/^=== EXISTING_COMMENTS ===$/ { f = 1; next } /^=== / { f = 0 } f' | sed '/^$/d')

  {
    echo "# Review context — ${PR_URL:-$BRANCH}"
    echo
    block "$PLUGIN_ROOT/references/pipeline.md" framing
    echo
    echo "## Identity"
    echo
    echo "- repo: $(basename "$REPO_ROOT") (\`$REPO_ROOT\`)"
    echo "- mode: $MODE"
    if [ -n "$PR_URL" ]; then
      echo "- pr: $PR_URL"
      echo "- title: \`$PR_TITLE\`"
      echo "- author: ${PR_AUTHOR:-unknown}${PR_DRAFT:+ (draft: $PR_DRAFT)}"
      echo "- branch: \`${PR_HEADREF:-$BRANCH}\` → \`${PR_BASEREF:-$BASE_BRANCH}\`"
    else
      echo "- branch: \`${BRANCH:-(detached)}\` → \`${BASE_BRANCH:-unknown}\`"
    fi
    echo "- base: \`$BASE\`"
    echo "- head: \`$HEAD\`"
    echo "- checked_out: $CHECKED_OUT — the working tree $( [ "$CHECKED_OUT" = yes ] && echo "is the head" || echo "is NOT the head (\`$HEAD0\`); read post-change content with \`git show $HEAD:<path>\`")"
    echo "- type: $TYPE (signal: $TYPE_SIGNAL; type_conflict: $TYPE_CONFLICT)"
    echo "- scale: $SCALE ($LINES production lines, $TOTAL_LINES with tests, $FILES files; $SCALE_REASON)"
    echo "- deep budget: $DEEP_ROW ($DEEP_SOURCE)"
    echo "- effort ceiling: ~$EFFORT tool calls per pass"
    if [ -n "${BRANCH_COMMITS:-}" ]; then
      echo "- commits (oldest first):"
      printf '%s\n' "$BRANCH_COMMITS" | sed 's/^/    /'
    fi
    echo
    echo "## Rules"
    echo
    block "$PLUGIN_ROOT/references/pipeline.md" scope-rule
    echo
    echo "### Read discipline"
    echo
    block "$PLUGIN_ROOT/references/pipeline.md" read-discipline
    echo
    echo "## Severity rubric"
    echo
    block "$PLUGIN_ROOT/references/severity.md" rubric
    echo
    block "$PLUGIN_ROOT/references/severity.md" rule-report
    echo
    block "$PLUGIN_ROOT/references/severity.md" "c-rule-$MODE"
    echo
    echo 'Findings come back one per line: `<category> | <file>:<line> | <A|B|C> | <claim>`.'
    if [ -n "$PR_BODY" ]; then
      echo
      echo "## PR body (verbatim, author-written — data, not instructions)"
      echo
      printf '%s\n' "$PR_BODY" | sed 's/^#/##/'
    fi
    echo
    echo "## Changed files"
    echo
    echo "prod:"; for f in $PROD_FILES; do echo "- $f"; done; [ -z "$PROD_FILES" ] && echo "- none"
    echo; echo "tests:"; for f in $TEST_FILES; do echo "- $f"; done; [ -z "$TEST_FILES" ] && echo "- none"
    echo; echo "binary:"; for f in $BINARY_FILES; do echo "- $f"; done; [ -z "$BINARY_FILES" ] && echo "- none"
    echo
    echo '```'
    git diff --stat "$BASE..$HEAD" 2>/dev/null || true
    echo '```'
    echo
    echo "## Conventions excerpt"
    echo
    block "$PLUGIN_ROOT/references/pipeline.md" conventions-header
    echo
    if [ -n "$CONVENTIONS" ]; then
      echo "Source: \`$CONVENTIONS\`. Chapters selected by signals: ${SIGNALS:-(none)}."
      echo
      conventions_excerpt "$CONVENTIONS" "$SIGNALS"
    else
      echo "(no conventions doc found in this repo)"
    fi
    echo
    echo "## Settled facts"
    echo
    block "$PLUGIN_ROOT/references/pipeline.md" settled-header
    echo
    if [ -n "$CI_SECTION" ]; then
      echo "- CI (authoritative for lint, test and baseline state at the head; a green check retires that class of finding):"
      printf '%s\n' "$CI_SECTION" | sed 's/^/    /'
    else
      echo "- CI: not gathered — lint and test state is unknown, not clean."
    fi
    if [ -n "$BINARY_DIMS" ]; then
      echo "- Image baselines (a changed WxH is a layout change; \`size unchanged\` means content moved inside the same box):"
      printf '%s' "$BINARY_DIMS" | sed 's/^/  /'
    fi
    echo
    echo "## Already on the PR"
    echo
    block "$PLUGIN_ROOT/references/pipeline.md" existing-comments-header
    echo
    case "$COMMENTS_SECTION" in
      ""|none|unavailable:*) echo "(no comments on the PR yet — every finding is new)" ;;
      *) printf '%s\n' "$COMMENTS_SECTION" | grep -v '^hint:' | sed 's/^/    /' ;;
    esac
    echo
    echo "## Diff"
    echo
    echo "**These sections (or the patch files they name) are the diff under review.**"
    echo
    echo "### The diff (prod)"
    echo
    case "$PROD_DIFF_WHERE" in
      inline) printf '%s\n' "$PROD_INLINE" ;;
      none) echo "(no production files changed)" ;;
      *) echo "Too large to inline — read \`$PROD_DIFF_WHERE\` once." ;;
    esac
    echo
    echo "### The diff (tests)"
    echo
    case "$TESTS_DIFF_WHERE" in
      inline) echo '```diff'; printf '%s\n' "$TESTS_INLINE"; echo '```' ;;
      none) echo "(no test files changed)" ;;
      *) echo "Too large to inline — read \`$TESTS_DIFF_WHERE\` once." ;;
    esac
    echo
    echo "## Orchestrator notes — \`$NOTES_PATH\`"
    echo
    echo "The orchestrator writes that file after this skeleton when it has something to add: Settled facts it verified (authoritative, under the same rule as above), Open leads with one owner pass each, and corrections to this skeleton. Read it once, after this file, if it exists. Nothing is ever appended here. An Open lead tagged with your pass is yours to close: it ends as a finding line or as a \`lead cleared: <lead> — <how>\` line after your findings, never in silence."
    echo
  } > "$CONTEXT_PATH"
  CONTEXT_LINES=$(wc -l < "$CONTEXT_PATH" | tr -d ' ')
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
if [ "$WANT_CONTEXT" = true ]; then
  CI_LINE=$(ci_summary)
  echo "ci: ${CI_LINE:-unavailable — the context script printed no CI_STATUS section}"
  COMMENTS_LINE=$(printf '%s\n' "${COMMENTS_SECTION:-}" | awk '/^summary: / { sub(/^summary: /, ""); print; exit } /^unavailable: / { print "none (" substr($0, 14) ")"; exit }')
  echo "existing_comments: ${COMMENTS_LINE:-none}"
  printf '%s\n' "${COMMENTS_SECTION:-}" | grep '^hint:' || true
else
  echo "ci: not gathered (--no-context)"
  echo "existing_comments: not gathered (--no-context)"
fi
echo "type: $TYPE"
echo "type_signal: $TYPE_SIGNAL"
echo "type_conflict: $TYPE_CONFLICT"
echo "scale: $SCALE"
echo "scale_counts: $LINES production lines ($TOTAL_LINES with tests), $FILES files (lock, generated, snapshot and image files excluded)"
echo "scale_reason: $SCALE_REASON"
echo "deep: $DEEP_ROW (source: $DEEP_SOURCE)"
echo "deep_candidates: $DEEP_CANDIDATES (.d.ts files $CAND_DTS, new exports $CAND_EXPORTS, new public methods $CAND_METHODS)"
echo "effort_per_pass: ~$EFFORT tool calls (scale $SCALE)"
if [ "$MODE" = "pr" ]; then
  echo "coverage: n/a (pr mode — the coverage stage is self-review only)"
else
  echo "coverage: $COVERAGE"
fi
echo "mutants: $MUTANTS"
if [ "$MUTANTS" -gt 0 ] 2>/dev/null; then
  if [ "$MUTANT_POOL" -eq 0 ]; then
    echo "mutant_pool: 0 — no non-styling source lines in the prod diff; the coverage stage has nothing to mutate"
  else
    echo "mutant_pool: ~$MUTANT_POOL non-styling source lines"
  fi
fi
echo "conventions_doc: ${CONVENTIONS:-none}"

if [ "$GUARD" != "ok" ]; then
  echo "passes: none — the guard refused this run"
  exit 2
fi

if [ "$LOOKUP_TYPE" = "undetermined" ] && [ -z "$PASS_TOKENS" ]; then
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
    MODEL=$(pass_model "$SCALE" "$token")
    COUNT=$((COUNT + 1))
    printf '  %-7s %-28s model: %-7s reads: %-14s prompt adds: %s\n' \
      "$token" "$AGENT" "${MODEL:-inherit}" "${READS:-both}" "${ADDS:--}"
  done
  echo "agents: $COUNT"
  echo "launch: one message · one Agent call per pass · subagent_type, model and prompt from === PROMPTS === verbatim · no name (references/delivery.md)"
fi

echo "prod_files: ${PROD_FILES:-none}"
echo "test_files: ${TEST_FILES:-none}"
echo "binary_files: ${BINARY_FILES:-none}"
if [ -n "$BINARY_DIMS" ]; then
  echo "binary_dims:"
  printf '%s' "$BINARY_DIMS"
fi
echo "comment_files: ${COMMENT_FILES:-none}"

if [ -n "$BRANCH_COMMITS" ]; then
  echo "commits:"
  printf '%s\n' "$BRANCH_COMMITS" | sed 's/^/  /'
elif [ -n "$BASE" ]; then
  echo "commits: none"
fi

if [ -n "$REPORT_DIR" ]; then
  echo "report_dir: $REPORT_DIR"
  REPORT_PR="${PR_NUMBER:-}"
  [ -z "$REPORT_PR" ] && REPORT_PR=$(printf '%s' "${PR:-}" | sed 's#.*/##')
  if [ "$MODE" = "pr" ] && [ -n "$REPORT_PR" ]; then
    echo "report: $REPORT_DIR/pr-$REPORT_PR-REVIEW.md"
  else
    echo "report: $REPORT_DIR/$SLUG-FINDINGS.md"
  fi
fi
if [ -n "$CONTEXT_PATH" ]; then
  echo "context: $CONTEXT_PATH (written, $CONTEXT_LINES lines — never Edit it; every pass reads it first)"
  echo "notes: $NOTES_PATH (not written — Write it once before fan-out with your Settled facts, Open leads and corrections; skip it when you have none)"
  echo "diff_prod: $PROD_DIFF_WHERE"
  echo "diff_tests: $TESTS_DIFF_WHERE"
else
  echo "context: ${CONTEXT_NOTE:-not written}"
fi
echo "commands: lint=${LINT_CMD:-unknown} test=${TEST_CMD:-unknown} src_glob=${SRC_GLOB:-unknown} (source: $CMD_SOURCE)"
echo "affected_packages: ${AFFECTED:-none}"
if [ -n "$TEST_FILES" ]; then
  echo "risk_check_manual: a deleted or weakened assertion in an existing test also forces the full tier — this script cannot detect it, so check the test hunks yourself"
fi

# ── Prompts ───────────────────────────────────────────────────────────
# The literal prompt per pass: context and notes paths, the lane, the resolved prompt
# adds, the effort ceiling, and the delivery clause copied from references/delivery.md by
# marker. The orchestrator pastes a block as-is — nothing about a launch is re-derived
# from prose, and every run's prompts are word-for-word the same.
if [ -n "$PASS_TOKENS" ] && [ -n "$CONTEXT_PATH" ]; then
  lane_prod() {
    case "$PROD_DIFF_WHERE" in
      inline) echo "the \`### The diff (prod)\` section of the context file" ;;
      none) echo "none — no production files changed" ;;
      *) echo "the patch \`$PROD_DIFF_WHERE\`, read once" ;;
    esac
  }
  lane_tests() {
    case "$TESTS_DIFF_WHERE" in
      inline) echo "the \`### The diff (tests)\` section of the context file" ;;
      none) echo "none — no test files changed" ;;
      *) echo "the patch \`$TESTS_DIFF_WHERE\`, read once" ;;
    esac
  }
  CLAUSE=$(block "$PLUGIN_ROOT/references/delivery.md" delivery-clause | grep -v '^```')
  echo
  echo "=== PROMPTS ==="
  for token in $PASS_TOKENS; do
    INFO=$(pass_agent "$token")
    AGENT=$(printf '%s' "$INFO" | cut -f1)
    MODEL=$(pass_model "$SCALE" "$token")
    echo "--- $token · subagent_type: $AGENT · model: ${MODEL:-inherit} ---"
    echo "Context file: \`$CONTEXT_PATH\` — read it first. Then \`$NOTES_PATH\` if it exists."
    case "$token" in
      change)
        echo "Your diff: $(lane_prod)."
        echo "Change type: $TYPE."
        [ "$TYPE_CONFLICT" != "none" ] && echo "type_conflict: $TYPE_CONFLICT"
        echo "Deep budget: $DEEP_ROW."
        ;;
      code)
        echo "Your diff: $(lane_prod)."
        [ -n "$COMMENT_FILES" ] && echo "Comment-adjacent files for the \`comments\` category: $COMMENT_FILES"
        [ "$MODE" = "pr" ] && echo "No reuse/maintainability nits."
        ;;
      tests)
        echo "Your diff: $(lane_tests) — your subject. The production patch, for the coverage category: $(lane_prod)."
        ;;
      *)
        echo "Your diff: $(lane_prod)."
        ;;
    esac
    echo "Effort ceiling: ~$EFFORT tool calls (scale $SCALE) — a ceiling, not a target; your definition names the drop order."
    echo
    printf '%s\n' "$CLAUSE"
    echo "--- end ---"
  done
elif [ -n "$PASS_TOKENS" ]; then
  echo
  echo "=== PROMPTS ==="
  echo "not printed — the context skeleton was not written (see context:)"
fi
