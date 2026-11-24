# policy.sh: sourced by review-plan.sh. The review policy: the pass registry, the passes and
# budgets of a mode and a change type, the caps of each scale tier, the model and the
# effort ceiling of each pass. The plan prints what this file resolves, so no skill
# restates it. Why the numbers look like this: docs/rationale.md.
#
# Reads: MODE, TYPE, SCALE, PLUGIN_NAME, BASE, HEAD, CHANGED, PROD_FILES, TEST_FILES,
#        BINARY_FILES, CODE_RE, ROUNDS_FLAG, NO_COVERAGE
# Sets: LOOKUP_TYPE, PASS_TOKENS, PASSES_DROPPED, DEEP_ROW, DEEP_SOURCE, EFFORT,
#       ROUNDS, MUTANTS, MUTANT_POOL

# The pass registry: the id, the agent and the lane that the pass reads.
# The lane is the whole diff input of the pass. `prod` is the prepared production patch.
# `tests` is the prepared test patch. `both` is both patches. `prod+comments` is the
# production patch plus the plan's `comment_files`, diffed directly. A pass never reads a
# patch outside its lane, and never regenerates a patch with `git diff` (pipeline.md §2).
# The agent is the bare name. The plan prints `<plugin name>:<agent>` as the
# `subagent_type`. The prompt adds of each pass live in lib/prompts.sh.
pass_agent() {  # pass_agent <id> — the agent with the plugin prefix, a tab, the lane
  case "$1" in
    change) printf '%s:change-reviewer\tprod\n' "$PLUGIN_NAME" ;;
    code) printf '%s:code-reviewer\tprod+comments\n' "$PLUGIN_NAME" ;;
    tests) printf '%s:test-reviewer\tboth\n' "$PLUGIN_NAME" ;;
  esac
}

# The model of each pass by scale tier. The change pass carries the boundary and impact
# judgment, so it keeps the strongest model at every tier. The code and tests passes run a
# checklist over a diff that the skeleton already quotes. Below the full tier, a smaller
# model does that equally well. The orchestrator passes the model as the Agent tool's
# `model`.
pass_model() {  # pass_model <scale> <id>
  case "$1/$2" in
    full/change|full/code|full/tests) echo opus ;;
    */change) echo opus ;;
    */code|*/tests) echo sonnet ;;
  esac
}

# The row of a mode and a change type: the passes, then the mutant, deep and rounds
# budgets, separated by tabs. The scale tier caps the budgets in plan_policy.
# `undetermined` is a row in pr mode (the base passes still apply) but not in self mode,
# where the type picks the whole profile: the caller resolves it from the diff shape and
# re-runs with --type rather than getting a silently chosen profile.
# A round is one fan-out of the passes. One round does not find everything in a large
# feature. On four feature branches of vaadin/web-components, a second round on the same
# head found 61 new findings after 92 in the first, 19 of them B. So self/feature has 2.
policy_row() {  # policy_row <mode> <type>
  case "$1/$2" in
    self/feature) printf 'change code tests\t15\t3\t2\n' ;;
    self/fix) printf 'change code tests\t5\t3\t1\n' ;;
    self/refactor) printf 'change code tests\t10\t3\t1\n' ;;
    self/chore) printf 'change code tests\t0\t0\t1\n' ;;
    pr/feature|pr/fix|pr/refactor|pr/undetermined) printf 'change code tests\t0\t3\t1\n' ;;
    pr/chore) printf 'change code tests\t0\t0\t1\n' ;;
  esac
}

plan_policy() {
  LOOKUP_TYPE="$TYPE"

  local row rounds="" mutants=0
  row=$(policy_row "$MODE" "$LOOKUP_TYPE")
  PASS_TOKENS=""
  DEEP_ROW=0
  if [ -n "$row" ]; then
    PASS_TOKENS=$(printf '%s' "$row" | cut -f1)
    mutants=$(printf '%s' "$row" | cut -f2)
    DEEP_ROW=$(printf '%s' "$row" | cut -f3)
    rounds=$(printf '%s' "$row" | cut -f4)
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

  # Rounds, self mode only: the row's number, capped by the scale tier. A small diff gives
  # a pass little to miss, so only the full tier repeats the fan-out. --rounds N sets it.
  case "$rounds" in ''|*[!0-9]*) rounds=1 ;; esac
  case "$SCALE" in trivial|lite) [ "$rounds" -gt 1 ] && rounds=1 ;; esac
  ROUNDS="${ROUNDS_FLAG:-$rounds}"

  # Coverage check, self mode only: the mutant budget of the row, capped by the scale tier.
  # --no-coverage sets it to 0.
  local cap
  case "$mutants" in ''|*[!0-9]*) mutants=0 ;; esac
  case "$SCALE" in trivial) cap=3 ;; lite) cap=8 ;; *) cap=999 ;; esac
  [ "$mutants" -gt "$cap" ] && mutants="$cap"
  [ "$NO_COVERAGE" = true ] && mutants=0
  MUTANTS="$mutants"
  MUTANT_POOL=0
  [ "$MODE" = self ] && [ "$MUTANTS" -gt 0 ] && MUTANT_POOL=$(mutant_pool)

  # Effective deep-block budget for the change pass: the row's number, capped by the
  # scale tier. The budget is a ceiling. The change pass selects the significant changes.
  case "$DEEP_ROW" in ''|*[!0-9]*) DEEP_ROW=0 ;; esac
  case "$SCALE" in trivial|lite) cap=1 ;; *) cap=999 ;; esac
  [ "$DEEP_ROW" -gt "$cap" ] && DEEP_ROW="$cap"
  DEEP_SOURCE="matrix, capped by scale"

  # Per-pass effort ceiling from the scale tier. The deep budget alone does not cap what a
  # single pass may spend. These are ceilings, not targets: a pass that answers its
  # checklist in six calls is complete. Each agents/<name>.md names what that pass drops
  # first. When the ceiling binds, a trivial or lite pass reports what it has. A full pass
  # also says which checklist sections it could not finish.
  case "$SCALE" in
    trivial) EFFORT=10 ;;
    lite) EFFORT=20 ;;
    *) EFFORT=30 ;;
  esac
  return 0
}

# The mutant candidate pool, advisory and not a budget: the non-styling source lines that
# the coverage check can mutate (mutation.md skips styling). A styling-only diff reports 0,
# so the check does not look for work that does not exist.
mutant_pool() {
  [ -n "$BASE" ] && [ -n "$PROD_FILES" ] || { echo 0; return 0; }
  # shellcheck disable=SC2086
  git diff --unified=0 "$BASE..$HEAD" -- $PROD_FILES 2>/dev/null | awk '
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
    END { print n + 0 }' || echo 0
}
