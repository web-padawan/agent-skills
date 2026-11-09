# prompts.sh: sourced by review-plan.sh. The prompt block of each pass.
#
# Reads: PASS_TOKENS, CONTEXT_PATH, NOTES_PATH, PROD_DIFF_WHERE, TESTS_DIFF_WHERE, TYPE,
#        TYPE_CONFLICT, DEEP_ROW, COMMENT_FILES, MODE, FORK, EFFORT, SCALE, PLUGIN_ROOT
# Sets: CLAUSE
#
# The literal prompt per pass: context and notes paths, the lane, the resolved prompt
# adds, the effort ceiling, and the delivery clause copied from references/delivery.md by
# marker. The orchestrator pastes a block as-is — nothing about a launch is re-derived
# from prose, and every run's prompts are word-for-word the same.

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

plan_prompts() {
  if [ -n "$PASS_TOKENS" ] && [ -n "$CONTEXT_PATH" ]; then
    CLAUSE=$(block "$PLUGIN_ROOT/references/delivery.md" delivery-clause | grep -v '^```')
    echo
    echo "=== PROMPTS ==="
    for token in $PASS_TOKENS; do
      INFO=$(pass_agent "$token")
      AGENT=$(printf '%s' "$INFO" | cut -f1)
      MODEL=$(pass_model "$SCALE" "$token")
      echo "--- $token · subagent_type: $AGENT · model: ${MODEL:-inherit} ---"
      echo "Context file: \`$CONTEXT_PATH\` — read it first. Then read \`$NOTES_PATH\` whole if it exists. Its Settled facts bind every pass, also a pass that owns no lead."
      echo "End your reply with one line that counts that file: \`notes: <n> settled, <m> leads\`, or \`notes: none\` when it does not exist."
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
  return 0
}
