# policy.sh: sourced by review-plan.sh. The review policy: the pass registry, the passes and
# budgets of a mode and a change type, the caps of each scale tier, the model and the
# effort ceiling of each pass. The plan prints what this file resolves, so no skill
# restates it. Why the numbers look like this: docs/rationale.md.
#
# Reads: MODE, TYPE, SCALE, PLUGIN_NAME, BASE, HEAD, CHANGED, PROD_FILES, TEST_FILES,
#        BINARY_FILES, CODE_RE, COVERAGE
# Sets: LOOKUP_TYPE, PASS_TOKENS, PASSES_DROPPED, MUTANTS, DEEP_ROW, DEEP_SOURCE,
#       CAND_DTS, CAND_EXPORTS, CAND_METHODS, DEEP_CANDIDATES, EFFORT,
#       STAGE_LIST

# The pass registry: the id, the agent and the lane that the pass reads.
# The lane is the whole diff input of the pass. `prod` is the prepared production patch.
# `tests` is the prepared test patch. `both` is both patches. `prod+comments` is the
# production patch plus the plan's `comment_files`, diffed directly. A pass never reads a
# patch outside its lane, and never regenerates a patch with `git diff` (pipeline.md §2).
# The agent is the bare name. The plan prints `<plugin name>:<agent>` as the
# `subagent_type`. The prompt adds of each pass live in the prompt block of review-plan.sh.
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
  STAGE_LIST=""

  local row rounds=""
  row=$(policy_row "$MODE" "$LOOKUP_TYPE")
  PASS_TOKENS=""
  MUTANTS=0
  DEEP_ROW=0
  if [ -n "$row" ]; then
    PASS_TOKENS=$(printf '%s' "$row" | cut -f1)
    MUTANTS=$(printf '%s' "$row" | cut -f2)
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

  # Stage rounds, self mode only: the row's number, capped by the scale tier. A small diff
  # gives a pass little to miss, so only the full tier repeats the fan-out. The skill maps
  # --rounds N to --budget rounds=N.
  case "$rounds" in ''|*[!0-9]*) rounds=1 ;; esac
  case "$SCALE" in trivial|lite) [ "$rounds" -gt 1 ] && rounds=1 ;; esac
  [ "$MODE" = self ] && STAGE_LIST="${STAGE_LIST:+$STAGE_LIST }rounds=$rounds"

  # Effective mutant budget: the row's number, capped by the scale tier.
  local cap
  case "$MUTANTS" in ''|*[!0-9]*) MUTANTS=0 ;; esac
  case "$SCALE" in trivial) cap=3 ;; lite) cap=8 ;; *) cap=999 ;; esac
  [ "$MUTANTS" -gt "$cap" ] && MUTANTS="$cap"
  [ "$COVERAGE" = "off" ] && MUTANTS=0
  [ "$MODE" != "self" ] && MUTANTS=0

  # Effective deep-block budget for the change pass: the row's number, capped by the
  # scale tier.
  case "$DEEP_ROW" in ''|*[!0-9]*) DEEP_ROW=0 ;; esac
  case "$SCALE" in trivial) cap=1 ;; lite) cap=2 ;; *) cap=999 ;; esac
  [ "$DEEP_ROW" -gt "$cap" ] && DEEP_ROW="$cap"
  DEEP_SOURCE="matrix, capped by scale"

  # Deep candidates — what the diff actually offers a boundary block: `.d.ts` files,
  # new exports, added public (non-underscore) methods at class indentation. A fix with
  # none of these gets one block for its top change instead of three surveys. The
  # effective budget is min(row, tier cap, max(1, candidates)).
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
        if (name ~ /^(if|for|while|switch|catch|return|super|constructor|render|connectedCallback|disconnectedCallback|attributeChangedCallback|firstUpdated|willUpdate|updated|requestUpdate|performUpdate)$/) next
        n++
      }
      END { print n + 0 }' || echo 0)
  fi
  DEEP_CANDIDATES=$((CAND_DTS + CAND_EXPORTS + CAND_METHODS))
  if [ "$DEEP_ROW" -gt 0 ]; then
    local cand_cap=$DEEP_CANDIDATES; [ "$cand_cap" -lt 1 ] && cand_cap=1
    if [ "$DEEP_ROW" -gt "$cand_cap" ]; then DEEP_ROW="$cand_cap"; DEEP_SOURCE="matrix, capped by scale and by $DEEP_CANDIDATES deep candidates"; fi
  fi

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

# ── Stages
# A stage is a step of a skill outside the fan-out, with a budget that the plan sets. The
# registry names the slot of the skill where the stage runs, whether the gate asks a
# question for it, and the reference file that holds its steps. plan_policy lists the
# stages of a profile in STAGE_LIST as <name>=<budget> words. docs/contracts.md holds the
# stage contract.
stage_info() {  # stage_info <name> — the slot, the ask flag and the reference, tab-separated
  case "$1" in
    rounds) printf 'after-triage\tno\tskills/self-review/references/rounds.md\n' ;;
  esac
}

stage_check_flags() {  # stage_check_flags — exit 1 on an unknown stage or a bad budget
  local s pair
  for s in $OFF_STAGES; do
    [ -n "$(stage_info "$s")" ] || { echo "error: --off: unknown stage $s" >&2; exit 1; }
  done
  for pair in $BUDGET_FLAGS; do
    [[ "$pair" =~ ^[a-z][a-z0-9-]*=[0-9]+$ ]] || { echo "error: --budget takes <stage>=<number>, got $pair" >&2; exit 1; }
    [ -n "$(stage_info "${pair%%=*}")" ] || { echo "error: --budget: unknown stage ${pair%%=*}" >&2; exit 1; }
  done
  return 0
}

# Reads: STAGE_LIST, OFF_STAGES, BUDGET_FLAGS, SCRIPT_DIR, BASE, HEAD, PROD_FILES,
#        TEST_FILES, FINDINGS_FILE, EARLIER_MODE
# Sets: STAGE_LIST, STAGES_OUT
plan_stages() {
  local entry name budget pair kept="" slot ask ref out
  for entry in $STAGE_LIST; do
    name="${entry%%=*}"; budget="${entry#*=}"
    case " $OFF_STAGES " in *" $name "*) continue ;; esac
    for pair in $BUDGET_FLAGS; do [ "${pair%%=*}" = "$name" ] && budget="${pair#*=}"; done
    kept="$kept $name=$budget"
  done
  STAGE_LIST="${kept# }"
  STAGES_OUT=""
  # The findings file only when the plan read it: not with --fresh, not when unreadable.
  local findings=""
  case "$EARLIER_MODE" in same|delta|rewritten) findings="$FINDINGS_FILE" ;; esac
  for entry in $STAGE_LIST; do
    name="${entry%%=*}"; budget="${entry#*=}"
    IFS=$'\t' read -r slot ask ref <<< "$(stage_info "$name")"
    STAGES_OUT="${STAGES_OUT}  $name: slot $slot, budget $budget, ask $ask, ref $ref
"
    [ -x "$SCRIPT_DIR/stages/$name.sh" ] || continue
    # shellcheck disable=SC2086
    out=$(FACTS_PROD=$(printf '%s\n' $PROD_FILES | sed '/^$/d') FACTS_TESTS=$(printf '%s\n' $TEST_FILES | sed '/^$/d') \
      STAGE_FINDINGS="$findings" "$SCRIPT_DIR/stages/$name.sh" --base "$BASE" --head "$HEAD" --budget "$budget" 2>&1) \
      || out="error: stages/$name.sh failed — $(printf '%s' "$out" | tail -1)"
    [ -n "$out" ] && STAGES_OUT="${STAGES_OUT}$(printf '%s\n' "$out" | sed 's/^/    /')
"
  done
  return 0
}
