# prompts.sh: sourced by review-plan.sh. The prompt block of each pass.
#
# Reads: PASS_TOKENS, CONTEXT_PATH, PROD_DIFF_WHERE, TESTS_DIFF_WHERE, TYPE, COMMENT_FILES,
#        EFFORT, SCALE, PLUGIN_ROOT
# Sets: CLAUSE
#
# The literal prompt per pass: the context path, the lane, the prompt adds, the effort
# ceiling, the slots for the Settled facts and Open leads of the orchestrator, and the
# delivery clause copied from references/review-rules.md by marker. The orchestrator fills
# the two slots and changes nothing else (review-rules.md §2).

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
    CLAUSE=$(block "$PLUGIN_ROOT/references/review-rules.md" delivery-clause | grep -v '^```')
    echo
    echo "=== PROMPTS ==="
    for token in $PASS_TOKENS; do
      INFO=$(pass_agent "$token")
      AGENT=$(printf '%s' "$INFO" | cut -f1)
      MODEL=$(pass_model "$SCALE" "$token")
      echo "--- $token · subagent_type: $AGENT · model: ${MODEL:-inherit} ---"
      echo "Context file: \`$CONTEXT_PATH\` — read it first."
      case "$token" in
        change)
          echo "Your diff: $(lane_prod)."
          echo "Change type: $TYPE."
          ;;
        code)
          echo "Your diff: $(lane_prod)."
          [ -n "$COMMENT_FILES" ] && echo "Comment-adjacent files for the \`comments\` category: the \`comment-adjacent\` list of the \`## Changed files\` section of the context file."
          ;;
        tests)
          echo "Your diff: $(lane_tests) — your subject. The production diff, for the coverage category: $(lane_prod)."
          ;;
        *)
          echo "Your diff: $(lane_prod)."
          ;;
      esac
      echo "Effort ceiling: ~$EFFORT tool calls (scale $SCALE) — a ceiling, not a target."
      echo
      echo "Settled facts:"
      echo "- none"
      echo "Open leads:"
      echo "- none"
      echo
      printf '%s\n' "$CLAUSE"
      echo "--- end ---"
    done
  elif [ -n "$PASS_TOKENS" ]; then
    echo
    echo "=== PROMPTS ==="
    echo "not printed — the context file was not written (see context:)"
  fi
  return 0
}
