# policy.sh: sourced by review-plan.sh. The review policy: the pass registry, the passes and
# the round budget of a mode and a change type, the model and the effort ceiling of each
# pass. The plan prints what this file resolves, so no skill restates it. Why the numbers
# look like this: docs/lessons.md.
#
# Reads: MODE, TYPE, SCALE, FORK, PLUGIN_NAME, CHANGED, PROD_FILES, TEST_FILES,
#        BINARY_FILES, CODE_RE, ROUNDS_FLAG
# Sets: LOOKUP_TYPE, PASS_TOKENS, PASSES_DROPPED, EFFORT, ROUNDS

# The pass registry: the id, the agent and the lane that the pass reads.
# The lane is the whole diff input of the pass. `prod` is the prepared production diff.
# `both` is the production and the test diff. `prod+comments` is the production diff plus
# the plan's `comment_files`. A pass never reads a diff outside its lane, and never runs
# `git diff` itself. The plan prints `<plugin name>:<agent>` as the `subagent_type`.
# The prompt adds of each pass live in lib/prompts.sh.
pass_agent() {  # pass_agent <id> — the agent with the plugin prefix, a tab, the lane
  case "$1" in
    change) printf '%s:change-reviewer\tprod\n' "$PLUGIN_NAME" ;;
    code) printf '%s:code-reviewer\tprod+comments\n' "$PLUGIN_NAME" ;;
    tests) printf '%s:test-reviewer\tboth\n' "$PLUGIN_NAME" ;;
  esac
}

# The model of each pass by scale tier. The change pass carries the behavior and consumer
# judgment, so it keeps the strongest model at every tier. Below the full tier, a smaller
# model runs the checklists of the code and tests passes equally well.
pass_model() {  # pass_model <scale> <id>
  case "$1/$2" in
    full/*) echo opus ;;
    */change) echo opus ;;
    */code|*/tests) echo sonnet ;;
  esac
}

# The row of a mode and a change type: the passes, a tab, the round budget.
# `undetermined` is a row in pr mode but not in self mode. There the type picks the
# checklists, so the caller resolves it from the diff shape and runs the plan again.
# A round is one fan-out of the passes. On four feature branches, a second round on the
# same head found 61 new findings after 92, so self/feature has 2 rounds.
# pr mode has no code pass on a same-repo PR: it gave 4 of 44 posted threads. A fork PR keeps
# it, because reuse findings decide a fork PR (plan_policy).
policy_row() {  # policy_row <mode> <type>
  case "$1/$2" in
    self/feature) printf 'change code tests\t2\n' ;;
    self/fix|self/refactor|self/chore) printf 'change code tests\t1\n' ;;
    pr/*) printf 'change tests\t1\n' ;;
  esac
}

plan_policy() {
  LOOKUP_TYPE="$TYPE"
  local row rounds=1
  row=$(policy_row "$MODE" "$LOOKUP_TYPE")
  PASS_TOKENS=""
  if [ -n "$row" ]; then
    PASS_TOKENS=$(printf '%s' "$row" | cut -f1)
    rounds=$(printf '%s' "$row" | cut -f2)
  fi
  if [ "$MODE" = pr ] && [ "$FORK" = true ] && [ -n "$PASS_TOKENS" ]; then
    PASS_TOKENS="change code tests"
  fi

  # The tests pass has no subject when no test, no code and no baseline changed: a workflow,
  # a config or a doc change. The risk override still raises the scale for the other passes.
  PASSES_DROPPED=""
  if [ -n "$CHANGED" ] && [ -z "$TEST_FILES" ] && [ -z "$BINARY_FILES" ] \
    && ! printf '%s\n' $PROD_FILES | grep -qE "$CODE_RE" \
    && [[ " $PASS_TOKENS " == *" tests "* ]]; then
    PASS_TOKENS=$(printf '%s\n' $PASS_TOKENS | grep -vx tests | tr '\n' ' ' | sed 's/ $//')
    PASSES_DROPPED="tests (no test, code or binary file changed)"
  fi

  # Rounds, self mode only: a small diff gives a pass little to miss, so only the full tier
  # repeats the fan-out. --rounds N sets the budget at any tier.
  case "$SCALE" in trivial|lite) rounds=1 ;; esac
  ROUNDS="${ROUNDS_FLAG:-$rounds}"

  # The effort ceiling of each pass, from the scale tier. It is a ceiling, not a target.
  case "$SCALE" in
    trivial) EFFORT=10 ;;
    lite) EFFORT=20 ;;
    *) EFFORT=30 ;;
  esac
  return 0
}
