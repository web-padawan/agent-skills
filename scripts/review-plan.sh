#!/usr/bin/env bash
# review-plan.sh — compute the review plan for a review skill: the anchors, the change type,
# the scale tier, the passes with their agents, models and read lanes, the round budget, the
# guards, and the report paths.
#
# The policy that it resolves lives in scripts/lib/policy.sh, so no skill restates it.
# The modules in scripts/lib/ run in this order: anchors, lanes, classify, policy, facts,
# store, context, prompts. Each one defines plan_<module>, and its header names the
# variables that it reads and sets.
#
# Usage:
#   review-plan.sh [--mode self|pr] [--pr <number-or-url>]
#                  [--type fix|feature|refactor|chore] [--rounds <n>]
#                  [--report-dir <path>] [--no-context] [--context-out <path>] [--no-write]
#
# It prints the diff facts of scripts/diff-facts.sh and its fact packs in both modes. In pr
# mode it also prints the screening facts of scripts/pr-screen.sh, and `fork:`. A fork PR
# keeps the code pass, and the plan writes the fork marker that scripts/hooks/bash-guard.py
# reads. A pr-mode run on a same-repo PR removes it, and it expires after 3 hours. A fork
# head that is the working tree refuses: its project settings loaded at session start.
# When no test, code or binary file changed, it drops the tests pass.
#
# It prints get-pr-context.sh's PR_METADATA, CI_STATUS and EXISTING_COMMENTS sections (skip
# with --no-context), then === PLAN ===. It writes the context file that the passes read at
# the `context:` path. `--context-out` picks the path, and `--no-write` skips it. For a large
# diff, it writes two patch files beside the context file, and it deletes the patches of an
# earlier context. After the plan it prints === PROMPTS ===: the literal prompt of each pass,
# with its agent and model. The orchestrator fills the Settled facts and Open leads slots of
# each prompt (references/review-rules.md §2). It never stages, commits, or touches tracked
# files.
#
# Plan keys, one `key: value` line each after === PLAN ===. An indented line belongs to the
# key above it. A key prints only when it applies:
#   mode guard note branch head0 base head base_branch pr fork hint ci existing_comments
#   screening diff_facts type type_signal scale scale_counts scale_reason effort_per_pass
#   rounds conventions_doc owner_rules passes agents passes_dropped launch prod_files
#   test_files binary_files comment_files commits findings report_dir report context
#   diff_prod diff_tests commands prod_source risk_check_manual
#
# Exit codes: 0 ok · 1 usage/environment error · 2 guard refused the run.
set -euo pipefail

MODE="self"
PR=""
TYPE_FLAG=""
REPORT_DIR=""
WANT_CONTEXT=true
CONTEXT_OUT=""
NO_WRITE=false
ROUNDS_FLAG=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode) MODE="${2:?--mode requires a value}"; shift 2 ;;
    --pr) PR="${2:?--pr requires a value}"; shift 2 ;;
    --type) TYPE_FLAG="${2:?--type requires a value}"; shift 2 ;;
    --report-dir) REPORT_DIR="${2:?--report-dir requires a value}"; shift 2 ;;
    --no-context) WANT_CONTEXT=false; shift ;;
    --context-out) CONTEXT_OUT="${2:?--context-out requires a value}"; shift 2 ;;
    --no-write) NO_WRITE=true; shift ;;
    --rounds) ROUNDS_FLAG="${2:?--rounds requires a number}"; shift 2 ;;
    --help|-h) sed -n '2,/^set -euo pipefail$/{/^set /d;p;}' "$0"; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

case "$MODE" in self|pr) ;; *) echo "error: --mode must be self or pr" >&2; exit 1 ;; esac
case "$TYPE_FLAG" in ""|fix|feature|refactor|chore) ;; *) echo "error: --type must be fix, feature, refactor or chore" >&2; exit 1 ;; esac
[[ -z "$ROUNDS_FLAG" || "$ROUNDS_FLAG" =~ ^[1-9][0-9]*$ ]] || { echo "error: --rounds takes a number above 0, got $ROUNDS_FLAG" >&2; exit 1; }

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PLUGIN_ROOT=$(dirname "$SCRIPT_DIR")
# shellcheck source=lib/lanes.sh
. "$SCRIPT_DIR/lib/lanes.sh"
# shellcheck source=lib/owner.sh
. "$SCRIPT_DIR/lib/owner.sh"
# shellcheck source=lib/policy.sh
. "$SCRIPT_DIR/lib/policy.sh"
# shellcheck source=lib/anchors.sh
. "$SCRIPT_DIR/lib/anchors.sh"
# shellcheck source=lib/classify.sh
. "$SCRIPT_DIR/lib/classify.sh"
# shellcheck source=lib/facts.sh
. "$SCRIPT_DIR/lib/facts.sh"
# shellcheck source=lib/store.sh
. "$SCRIPT_DIR/lib/store.sh"
# shellcheck source=lib/context.sh
. "$SCRIPT_DIR/lib/context.sh"
# shellcheck source=lib/prompts.sh
. "$SCRIPT_DIR/lib/prompts.sh"
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

# ── Policy: passes, rounds, models, effort (lib/policy.sh) ───────────
plan_policy

# ── Facts: conventions, diff, screening, commands (lib/facts.sh)
plan_facts

# ── Report paths (lib/store.sh) ───────────────────────────────────────
plan_store

# ── Context file (lib/context.sh) ────────────────────────────────────
plan_context

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
echo "type: $TYPE"
echo "type_signal: $TYPE_SIGNAL"
echo "scale: $SCALE"
echo "scale_counts: $LINES production lines ($TOTAL_LINES with tests), $FILES files, $PROD_FILE_COUNT production (lock, generated, snapshot and image files excluded)"
echo "scale_reason: $SCALE_REASON"
echo "effort_per_pass: ~$EFFORT tool calls (scale $SCALE)"
[ "$MODE" = self ] && echo "rounds: $ROUNDS"
echo "conventions_doc: $([ -n "$CONVENTIONS" ] && printf '%s' "$CONVENTIONS" | sed 's/ /, /g' || echo none)"
echo "owner_rules: ${OWNER_RULES:-none}"

if [ "$GUARD" != "ok" ]; then
  echo "passes: none — the guard refused this run"
  exit 2
fi

if [ "$LOOKUP_TYPE" = "undetermined" ] && [ -z "$PASS_TOKENS" ]; then
  echo "passes: none — resolve the type from the diff shape (references/review-rules.md §1) and run the plan again with --type"
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
  echo "launch: one message · one Agent call per pass · subagent_type, model and prompt from === PROMPTS === · fill the Settled facts and Open leads of each prompt, change nothing else · no name (references/review-rules.md §2 and §3)"
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
  echo "diff_prod: $PROD_DIFF_WHERE"
  echo "diff_tests: $TESTS_DIFF_WHERE"
else
  echo "context: ${CONTEXT_NOTE:-not written}"
fi
echo "commands: lint=${LINT_CMD:-unknown} test=${TEST_CMD:-unknown} src_glob=${SRC_GLOB:-unknown} (source: $CMD_SOURCE)"
echo "prod_source: $PROD_SOURCE"
if [ -n "$TEST_FILES" ]; then
  echo "risk_check_manual: a deleted or weakened assertion in an existing test also forces the full tier — this script cannot detect it, so check the test hunks yourself"
fi

# ── Prompts (lib/prompts.sh) ──────────────────────────────────────────
plan_prompts
