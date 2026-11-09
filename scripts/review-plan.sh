#!/usr/bin/env bash
# review-plan.sh — compute the review plan for a review skill: the anchors, the
# change type, the scale tier, the pass list with its agents and read lanes, the
# mutant and deep-block budgets, the guards, and the report paths.
#
# The policy it resolves lives in scripts/lib/policy.sh, so no skill restates it.
#
# Usage:
#   review-plan.sh [--mode self|pr] [--pr <number-or-url>]
#                  [--type fix|feature|refactor|chore]
#                  [--rounds N] [--fresh] [--no-coverage] [--report-dir <path>]
#                  [--no-context] [--context-out <path>] [--no-write]
#
# When a file under .github/workflows/ changed, it prints the `workflow:` facts of
# scripts/workflow-facts.sh. When no test, code or binary file changed, it drops the tests pass.
#
# It prints the diff facts of scripts/diff-facts.sh and its fact packs in both modes.
# In pr mode it also prints the screening facts of scripts/pr-screen.sh, and `fork:`. A fork
# PR keeps reuse and maintainability in the code pass, and writes the fork marker that
# scripts/hooks/bash-guard.py reads. A pr-mode run on a same-repo PR removes it, and it
# expires after 3 hours. A fork head that is the
# working tree refuses: its project settings loaded at session start.
#
# In self mode it also reads the findings file of the last review of the branch
# (`<report-dir>/<branch>-findings.json`): the same head starts a further round, a newer
# head reconciles the earlier findings. `--fresh` ignores the file.
#
# Prints get-pr-context.sh's PR_METADATA, CI_STATUS and EXISTING_COMMENTS sections (skip
# with --no-context; the other sections are restated by the plan) then === PLAN ===, and
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
COVERAGE="on"
REPORT_DIR=""
WANT_CONTEXT=true
CONTEXT_OUT=""
NO_WRITE=false
ROUNDS_FLAG=""
FRESH=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode) MODE="${2:?--mode requires a value}"; shift 2 ;;
    --pr) PR="${2:?--pr requires a value}"; shift 2 ;;
    --type) TYPE_FLAG="${2:?--type requires a value}"; shift 2 ;;
    --rounds) ROUNDS_FLAG="${2:?--rounds requires a value}"; shift 2 ;;
    --fresh) FRESH=true; shift ;;
    --no-coverage) COVERAGE="off"; shift ;;
    --report-dir) REPORT_DIR="${2:?--report-dir requires a value}"; shift 2 ;;
    --no-context) WANT_CONTEXT=false; shift ;;
    --context-out) CONTEXT_OUT="${2:?--context-out requires a value}"; shift 2 ;;
    --no-write) NO_WRITE=true; shift ;;
    --help|-h) sed -n '2,/^set -euo pipefail$/{/^set /d;p;}' "$0"; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

case "$MODE" in self|pr) ;; *) echo "error: --mode must be self or pr" >&2; exit 1 ;; esac
case "$TYPE_FLAG" in ""|fix|feature|refactor|chore) ;; *) echo "error: --type must be fix, feature, refactor or chore" >&2; exit 1 ;; esac
if [ -n "$ROUNDS_FLAG" ] && ! [[ "$ROUNDS_FLAG" =~ ^[1-9][0-9]*$ ]]; then
  echo "error: --rounds takes a number of 1 or more" >&2; exit 1
fi

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PLUGIN_ROOT=$(dirname "$SCRIPT_DIR")
# shellcheck source=lib/lanes.sh
. "$SCRIPT_DIR/lib/lanes.sh"
# shellcheck source=lib/policy.sh
. "$SCRIPT_DIR/lib/policy.sh"
# shellcheck source=lib/anchors.sh
. "$SCRIPT_DIR/lib/anchors.sh"
# shellcheck source=lib/classify.sh
. "$SCRIPT_DIR/lib/classify.sh"
# shellcheck source=lib/facts.sh
. "$SCRIPT_DIR/lib/facts.sh"
# The plugin name prefixes each agent of lib/policy.sh and names the fork marker directory.
PLUGIN_NAME=$(jq -r '.name // empty' "$PLUGIN_ROOT/.claude-plugin/plugin.json" 2>/dev/null || true)
[ -n "$PLUGIN_NAME" ] || { echo "error: no plugin name in $PLUGIN_ROOT/.claude-plugin/plugin.json" >&2; exit 1; }

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "error: not a git repository" >&2; exit 1; }
cd "$REPO_ROOT"

# ── Anchors, guards and the fork marker (lib/anchors.sh) ─────────────
plan_anchors

# ── File lanes ────────────────────────────────────────────────────────
plan_lanes

# ── Change type and scale (lib/classify.sh) ──────────────────────────
plan_classify

# ── Policy: passes, budgets, models, effort (lib/policy.sh) ──────────
plan_policy

# ── Facts: conventions, diff, screening, workflow, commands (lib/facts.sh)
plan_facts

# ── Report paths ──────────────────────────────────────────────────────
SLUG=$(printf '%s' "${BRANCH:-detached}" | tr '/' '-')
if [ -z "$REPORT_DIR" ]; then
  case "$MODE" in
    # The git directory is never tracked and belongs to one worktree, so the report of
    # each branch survives between runs without a .gitignore entry.
    self) REPORT_DIR=$(git rev-parse --path-format=absolute --git-path self-review 2>/dev/null) \
            || { echo "error: the self-review report dir needs git 2.31 or later" >&2; exit 1; } ;;
    # pr mode never writes into the repo: the review record is the reviewer's own,
    # never committed or posted (the Present step of pr-review).
    pr) REPORT_DIR="SCRATCHPAD" ;;
  esac
fi

# ── Earlier findings ──────────────────────────────────────────────────
# The findings file that the last self-review of this branch wrote
# (skills/self-review/references/finalize.md, "Findings file"). One review does not find
# everything, so the next one starts from it:
#   same      the head is unchanged: a further round. The earlier findings must not repeat.
#   delta     the head descends from the reviewed one: the author changed the branch. Each
#             pass reconciles the earlier findings of its categories, and C findings stay
#             on the lines changed since (the markers below).
#   rewritten the reviewed head is gone (rebase, force-push): reconcile, no line markers.
FINDINGS_FILE=""; EARLIER_MODE="none"; EARLIER_HEAD=""; EARLIER_COUNT=0; EARLIER_OPEN=0
EARLIER_LIST=""; CHANGED_SINCE=""; ROUND=1
if [ "$MODE" = "self" ] && [ "$REPORT_DIR" != "SCRATCHPAD" ] && [ -n "$HEAD" ]; then
  FINDINGS_FILE="$REPORT_DIR/$SLUG-findings.json"
  if [ ! -f "$FINDINGS_FILE" ]; then
    EARLIER_MODE="none"
  elif [ "$FRESH" = true ]; then
    EARLIER_MODE="ignored (--fresh)"
  elif ! command -v jq >/dev/null 2>&1; then
    EARLIER_MODE="unreadable (jq not found)"
  elif ! jq -e '.findings | type == "array"' "$FINDINGS_FILE" >/dev/null 2>&1; then
    EARLIER_MODE="unreadable (no findings array)"
  else
    EARLIER_HEAD=$(jq -r '.head // empty' "$FINDINGS_FILE")
    EARLIER_COUNT=$(jq '.findings | length' "$FINDINGS_FILE")
    EARLIER_OPEN=$(jq '[.findings[] | select(.status as $s | ["open", "not_fixed", "partially_fixed", "fixed_wrongly"] | index($s))] | length' "$FINDINGS_FILE")
    if [ "$EARLIER_HEAD" = "$HEAD" ]; then
      EARLIER_MODE="same"
      ROUND=$(( $(jq -r '.round // 1' "$FINDINGS_FILE") + 1 ))
    elif [ -n "$EARLIER_HEAD" ] && git merge-base --is-ancestor "$EARLIER_HEAD" "$HEAD" 2>/dev/null; then
      EARLIER_MODE="delta"
      # One line per file: the new-side line ranges that changed since the reviewed head.
      CHANGED_SINCE=$(git diff --unified=0 --no-renames "$EARLIER_HEAD..$HEAD" 2>/dev/null | awk '
        /^\+\+\+ b\// { f = substr($0, 7); next }
        /^\+\+\+ / { f = ""; next }
        /^@@/ && f != "" {
          split($3, a, ","); s = substr(a[1], 2) + 0; n = (a[2] == "" ? 1 : a[2] + 0)
          if (n > 0) r[f] = r[f] (r[f] == "" ? "" : ", ") (n > 1 ? s "-" (s + n - 1) : s)
        }
        END { for (f in r) print f ": " r[f] }' | sort)
    else
      EARLIER_MODE="rewritten"
    fi
    # A finding that triage merged into another one rides on the kept line, so a
    # further round sees it and does not report it again.
    EARLIER_LIST=$(jq -r '.findings[] | "\(.id) | \(.status) | \(.category) | \(.file // "-"):\(.line // "-") | \(.tier) | \(.claim)" + ([.merged[]? | " Merged: \(.file // "-"):\(.line // "-") \(.claim)"] | join(""))' "$FINDINGS_FILE")
  fi
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


# ── Context skeleton ──────────────────────────────────────────────────
# Everything deterministic about the shared context file (references/pipeline.md §2):
# the framing, identity, rules and rubric copied from the reference docs by marker,
# the PR body, the lanes, the diff (inline when small), the conventions doc when it is
# short, and the Settled facts this script can prove. The
# orchestrator appends only what it verified itself.
block() {  # block <doc> <name> — print one marked block from a reference doc, headings demoted
  awk -v name="$2" '
    index($0, "<!-- block:" name " -->") == 1 { f = 1; next }
    /^<!-- \/block -->/ { f = 0 }
    f' "$1" | sed 's/^#/##/'
}

conventions_excerpt() {  # conventions_excerpt <doc> — the doc quoted whole, with line numbers
  # A doc that fits the budget is quoted whole: a missed "when you add X, also update Y"
  # rule is a missed finding (the upstream Vaadin CI review reads the whole doc for the
  # same reason). A longer doc is named only.
  if [ "$(wc -l < "$1")" -le "$CONVENTIONS_WHOLE_MAX" ]; then
    awk '/^# / { next } /^#/ || /^[[:space:]]*$/ { print; next } { printf "%d| %s\n", NR, $0 }' "$1" | sed 's/^#/##/'
  else
    echo "(the conventions doc is over $CONVENTIONS_WHOLE_MAX lines — not quoted; open \`$1\` only for a finding that needs it)"
  fi
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
    block "$PLUGIN_ROOT/references/skeleton-blocks.md" framing
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
    if [ "$FORK" = "true" ]; then
      echo "- fork: true (\`${HEAD_REPO:-unknown}\`) — run no code of this head: no tests, no scripts, no package manager"
    elif [ "$FORK" = "false" ]; then
      echo "- fork: false"
    fi
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
    block "$PLUGIN_ROOT/references/skeleton-blocks.md" scope-rule
    echo
    echo "### Read discipline"
    echo
    block "$PLUGIN_ROOT/references/skeleton-blocks.md" read-discipline
    echo
    echo "## Severity rubric"
    echo
    block "$PLUGIN_ROOT/references/severity.md" rubric
    echo
    block "$PLUGIN_ROOT/references/skeleton-blocks.md" rule-report
    echo
    block "$PLUGIN_ROOT/references/skeleton-blocks.md" c-rule
    echo
    echo 'Findings come back one per line: `<category> | <file>:<line> | <A|B|C> | <claim>[ | src:<file>:<line>]`.'
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
    echo; echo "binary (never diffed):"
    for f in $BINARY_FILES; do echo "- $f"; done
    [ -z "$BINARY_FILES" ] && echo "- none"
    echo
    echo "$(git diff --shortstat "$BASE..$HEAD" 2>/dev/null | sed 's/^ *//')"
    echo
    echo "## Conventions excerpt"
    echo
    block "$PLUGIN_ROOT/references/skeleton-blocks.md" conventions-header
    echo
    if [ -n "$CONVENTIONS" ]; then
      if [ "$(wc -l < "$CONVENTIONS")" -le "$CONVENTIONS_WHOLE_MAX" ]; then
        echo "Source: \`$CONVENTIONS\`, quoted whole ($(wc -l < "$CONVENTIONS" | tr -d ' ') lines)."
      else
        echo "Source: \`$CONVENTIONS\`, not quoted ($(wc -l < "$CONVENTIONS" | tr -d ' ') lines, over $CONVENTIONS_WHOLE_MAX)."
      fi
      echo
      conventions_excerpt "$CONVENTIONS"
    else
      echo "(no conventions doc found in this repo)"
    fi
    if [ -n "$COMMENT_FILES" ]; then
      echo
      echo "## Comment policy"
      echo
      block "$PLUGIN_ROOT/references/comments.md" comment-policy
    fi
    echo
    echo "## Settled facts"
    echo
    block "$PLUGIN_ROOT/references/skeleton-blocks.md" settled-header
    echo
    if [ -n "$CI_SECTION" ]; then
      echo "- CI (authoritative for lint, test and baseline state at the head; a green check retires that class of finding):"
      printf '%s\n' "$CI_SECTION" | sed 's/^/    /'
    else
      echo "- CI: not gathered — lint and test state is unknown, not clean."
    fi
    if [ -n "$DIFF_FACTS" ]; then
      echo "- Diff facts (scripts/diff-facts.sh and its fact packs; a \`rule:\` line tells you how to judge the fact lines above it):"
      printf '%s\n' "$DIFF_FACTS" | sed 's/^/    /'
    fi
    if [ -n "$WORKFLOW_FACTS" ]; then
      echo "- Workflow (scripts/workflow-facts.sh; read each \`uses:\` action at its ref before a claim about its inputs or behavior):"
      printf '%s\n' "$WORKFLOW_FACTS" | sed 's/^/    /'
    fi
    echo
    echo "## Already on the PR"
    echo
    block "$PLUGIN_ROOT/references/skeleton-blocks.md" existing-comments-header
    echo
    case "$COMMENTS_SECTION" in
      ""|none|unavailable:*) echo "(no comments on the PR yet — every finding is new)" ;;
      *) printf '%s\n' "$COMMENTS_SECTION" | grep -v '^hint:' | sed 's/^/    /' ;;
    esac
    case "$EARLIER_MODE" in
      same|delta|rewritten)
        echo
        echo "## Earlier findings"
        echo
        if [ "$EARLIER_MODE" = "same" ]; then
          block "$PLUGIN_ROOT/references/skeleton-blocks.md" earlier-findings-same
        else
          block "$PLUGIN_ROOT/references/skeleton-blocks.md" earlier-findings-delta
        fi
        echo
        echo "Source: \`$FINDINGS_FILE\`, reviewed head \`${EARLIER_HEAD:0:10}\`. Each line: id | status | category | file:line | tier | claim. A \`Merged:\` entry after a claim is a finding that triage merged into it."
        echo
        if [ -n "$EARLIER_LIST" ]; then
          printf '%s\n' "$EARLIER_LIST" | sed '/^$/d; s/^/- /'
        else
          echo "- none: the review of \`${EARLIER_HEAD:0:10}\` had no finding"
        fi
        if [ "$EARLIER_MODE" = "delta" ]; then
          echo
          echo "### Changed since ${EARLIER_HEAD:0:10}"
          echo
          if [ -n "$CHANGED_SINCE" ]; then printf '%s\n' "$CHANGED_SINCE" | sed 's/^/- /'; else echo "- none"; fi
        elif [ "$EARLIER_MODE" = "rewritten" ]; then
          echo
          echo "The reviewed head is not an ancestor of this head, so no line is marked as changed since. Review the whole diff at full priority."
        fi
        ;;
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
if [ "$MODE" = "pr" ]; then
  echo "fork: ${FORK:-unknown}${HEAD_REPO:+ ($HEAD_REPO)}"
  if [ "$FORK" = "true" ]; then
    echo "hint: fork PR — never run yarn, npm, npx, pnpm or node on this head; the Bash guard holds the passes to read-only commands (fork marker: $FORK_MARKER)"
    echo "hint: fork PR — the code pass keeps reuse and maintainability"
  fi
fi
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
if [ -n "$SCREENING" ]; then
  echo "screening:"
  printf '%s\n' "$SCREENING" | grep -v '^fork: ' | sed 's/^/  /'
fi
if [ -n "$DIFF_FACTS" ]; then
  echo "diff_facts:"
  printf '%s\n' "$DIFF_FACTS" | sed 's/^/  /'
fi
if [ -n "$WORKFLOW_FACTS" ]; then
  echo "workflow:"
  printf '%s\n' "$WORKFLOW_FACTS" | sed 's/^/  /'
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
echo "round: $ROUND of $ROUNDS (rounds budget: $ROUNDS_SOURCE)"
case "$EARLIER_MODE" in
  same)
    if [ "$EARLIER_COUNT" -eq 0 ]; then echo "earlier_findings: same head — the earlier review of this head had no finding"
    else echo "earlier_findings: same head — $EARLIER_COUNT findings of the earlier rounds, listed so that no pass repeats them"; fi ;;
  delta) echo "earlier_findings: delta from ${EARLIER_HEAD:0:10} — $EARLIER_COUNT findings, $EARLIER_OPEN open to reconcile, $(printf '%s\n' "$CHANGED_SINCE" | grep -c . || true) files changed since" ;;
  rewritten) echo "earlier_findings: rewritten — ${EARLIER_HEAD:0:10} is not an ancestor of the head; $EARLIER_COUNT findings, $EARLIER_OPEN open to reconcile, no line markers" ;;
  *) echo "earlier_findings: $EARLIER_MODE" ;;
esac
[ -n "$FINDINGS_FILE" ] && echo "findings_file: $FINDINGS_FILE"
echo "conventions_doc: ${CONVENTIONS:-none}"

if [ "$GUARD" != "ok" ]; then
  echo "passes: none — the guard refused this run"
  exit 2
fi

if [ "$LOOKUP_TYPE" = "undetermined" ] && [ -z "$PASS_TOKENS" ]; then
  echo "passes: none — resolve the type from the diff shape (references/pipeline.md step 1) and re-run with --type"
elif [ -z "$PASS_TOKENS" ]; then
  echo "passes: none — no matrix row for $MODE/$LOOKUP_TYPE/$SCALE (check scripts/lib/policy.sh)"
else
  echo "passes:"
  COUNT=0
  for token in $PASS_TOKENS; do
    INFO=$(pass_agent "$token")
    AGENT=$(printf '%s' "$INFO" | cut -f1)
    READS=$(printf '%s' "$INFO" | cut -f2)
    [ -z "$AGENT" ] && AGENT="(no agent in scripts/lib/policy.sh for '$token')"
    MODEL=$(pass_model "$SCALE" "$token")
    COUNT=$((COUNT + 1))
    printf '  %-7s %-28s model: %-7s reads: %s\n' \
      "$token" "$AGENT" "${MODEL:-inherit}" "${READS:-both}"
  done
  echo "agents: $COUNT"
  [ -n "$PASSES_DROPPED" ] && echo "passes_dropped: $PASSES_DROPPED"
  echo "launch: one message · one Agent call per pass · subagent_type, model and prompt from === PROMPTS === verbatim · no name (references/delivery.md)"
fi

echo "prod_files: ${PROD_FILES:-none}"
echo "test_files: ${TEST_FILES:-none}"
echo "binary_files: ${BINARY_FILES:-none}"
echo "comment_files: ${COMMENT_FILES:-none}"

if [ -n "$BRANCH_COMMITS" ]; then
  echo "commits:"
  printf '%s\n' "$BRANCH_COMMITS" | sed 's/^/  /'
elif [ -n "$BASE" ]; then
  echo "commits: none"
fi

if [ "$MODE" = "pr" ]; then
  # The findings file sits beside the context file, which pr-review writes to its scratchpad.
  REPORT_PR="${PR_NUMBER:-}"
  [ -z "$REPORT_PR" ] && REPORT_PR=$(printf '%s' "${PR:-}" | sed 's#.*/##')
  if [ -n "$CONTEXT_PATH" ] && [ -n "$REPORT_PR" ]; then
    echo "findings: $(dirname "$CONTEXT_PATH")/pr-$REPORT_PR-findings.json"
  else
    echo "findings: not set — the plan wrote no context file (pass --context-out)"
  fi
elif [ -n "$REPORT_DIR" ]; then
  echo "report_dir: $REPORT_DIR"
  echo "report: $REPORT_DIR/$SLUG-FINDINGS.md"
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
        [ "$MODE" = "pr" ] && [ "$FORK" != "true" ] && echo "No reuse/maintainability nits."
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
