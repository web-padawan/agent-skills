# facts.sh: sourced by review-plan.sh. The conventions doc, the diff facts and their fact
# packs, the screening facts, the workflow facts, the command map and the affected packages.
#
# Reads: MODE, PR, WANT_CONTEXT, SCRIPT_DIR, BASE, HEAD, CHANGED, SCALE
# Sets: CONVENTIONS, CONVENTIONS_WHOLE_MAX, DIFF_FACTS, REACH_MAX, SCREENING, WORKFLOW_FACTS,
#       LINT_CMD, TEST_CMD, SRC_GLOB, CMD_SOURCE, AFFECTED

plan_facts() {
  # ── Conventions doc (named in the plan, quoted into the context)
  CONVENTIONS=""
  CONVENTIONS_WHOLE_MAX=400
  for f in .github/review-instructions.md .github/copilot-instructions.md CONVENTIONS.md CLAUDE.md AGENTS.md; do
    if [ -f "$f" ]; then CONVENTIONS="$f"; break; fi
  done

  # ── Diff facts
  # The facts of the diff that git alone answers (scripts/diff-facts.sh). The plan prints
  # them, and the skeleton quotes them whole under Settled facts, in both modes.
  DIFF_FACTS=""; REACH_MAX=0
  if [ -n "$BASE" ] && [ -n "$HEAD" ] && [ -n "$CHANGED" ]; then
    DIFF_FACTS=$(FACTS_MODE="$MODE" FACTS_PR="$PR" FACTS_OFFLINE="$([ "$WANT_CONTEXT" = true ] || echo 1)" \
      "$SCRIPT_DIR/diff-facts.sh" --base "$BASE" --head "$HEAD" 2>&1 | sed '/^=== DIFF_FACTS ===$/d') \
      || DIFF_FACTS="error: diff-facts.sh failed — $(printf '%s' "$DIFF_FACTS" | tail -1)"
    REACH_MAX=$(printf '%s\n' "$DIFF_FACTS" | sed -n 's/^reach_max: //p' | head -1)
    REACH_MAX=${REACH_MAX:-0}
  fi

  # ── Screening (pr mode)
  # What a maintainer must know before a review is worth it: the author, the linked issue,
  # the flags and the verdict hint. Only the plan prints it. The passes never learn the bar.
  SCREENING=""
  if [ "$MODE" = "pr" ] && [ -n "$PR" ] && [ "$WANT_CONTEXT" = true ]; then
    SCREENING_ARGS=(--pr "$PR" --reach-max "$REACH_MAX" --scale "$SCALE")
    SCREENING=$("$SCRIPT_DIR/pr-screen.sh" "${SCREENING_ARGS[@]}" 2>&1 | sed '/^=== SCREENING ===$/d') \
      || SCREENING="error: pr-screen.sh failed — $(printf '%s' "$SCREENING" | tail -1)"
  fi

  # ── Workflow facts
  # A workflow change depends on the actions it calls, the token of each job and who
  # triggers the runs. None of that is in the diff (retrospective, PR review 6).
  WORKFLOW_FACTS=""
  if [ -n "$BASE" ] && [ -n "$HEAD" ] && printf '%s\n' "$CHANGED" | grep -q '^\.github/workflows/'; then
    WF_ARGS=(--base "$BASE" --head "$HEAD")
    [ "$WANT_CONTEXT" = true ] || WF_ARGS+=(--no-gh)
    WORKFLOW_FACTS=$("$SCRIPT_DIR/workflow-facts.sh" "${WF_ARGS[@]}" 2>&1) \
      || WORKFLOW_FACTS="error: workflow-facts.sh failed — $(printf '%s' "$WORKFLOW_FACTS" | tail -1)"
  fi

  # ── Command map
  LINT_CMD=""; TEST_CMD=""; SRC_GLOB=""; CMD_SOURCE=""
  # Only the root manifest decides. The conventions doc names a per-package or a lint command.
  if [ -f pom.xml ]; then
    TEST_CMD="mvn test"; SRC_GLOB="**/src/main/**"
    CMD_SOURCE="Maven layout (root pom.xml)"
  elif [ -f package.json ]; then
    PM=npm; [ -f yarn.lock ] && PM=yarn; [ -f pnpm-lock.yaml ] && PM=pnpm
    RUN="$PM"; [ "$PM" = npm ] && RUN="npm run"
    jq -e '.scripts.lint' package.json >/dev/null 2>&1 && LINT_CMD="$RUN lint"
    jq -e '.scripts.test' package.json >/dev/null 2>&1 && TEST_CMD="$PM test"
    SRC_GLOB="src/**"
    ls -d packages/*/src >/dev/null 2>&1 && SRC_GLOB="packages/*/src/**"
    CMD_SOURCE="package.json scripts ($PM)"
  else
    CMD_SOURCE="no root manifest"
  fi
  CMD_SOURCE="$CMD_SOURCE; take a per-package or a missing command from ${CONVENTIONS:-CLAUDE.md or AGENTS.md}"

  AFFECTED=""
  if [ -n "$CHANGED" ]; then
    AFFECTED=$(printf '%s\n' "$CHANGED" | awk -F/ '$1 == "packages" && NF > 2 { print $1 "/" $2 }' | sort -u | tr '\n' ' ')
  fi
  return 0
}
