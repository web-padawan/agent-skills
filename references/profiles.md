# Review profiles — the single source

Two tables. Everything else in this plugin reads them from here, and
`scripts/review-plan.sh` parses them so no skill has to join them by hand.

- **Passes** — the pass id, the agent that runs it, and what its prompt must add
  beyond the context file path and the delivery clause. Every other contract
  (questions, category, output format, verification rules) lives in the agent
  definition at `agents/<name>.md`.
- **Matrix** — for a mode, change type and scale tier: which passes run, and the
  mutant budget. The plan script resolves a row into a launch list.

Pass token syntax, used in the matrix `passes` column:

- `general+scope+intent` — the pass runs and **folds** the listed passes' core
  questions into itself; findings still go under their own category. Fold ids are
  pass ids plus `reuse` (the cleanup pass's highest-value question).
- `pre:premise` — launched **alone, before** the rest of the batch; the batch waits
  for its verdict.
- `slop:sonnet` — launch this pass with `model: sonnet`. Judgment passes always keep
  the session default.
- `integration?` — run only when the repo has a conventions doc.

## Passes

| id | agent | prompt adds |
| --- | --- | --- |
| general | agent-skills:general-reviewer | the plan's `folds` list, when it is not `-`; on a fix also name the repo's conventions doc |
| scope | agent-skills:scope-reviewer | the plan's `type_conflict` line, when it is not `none` |
| intent | agent-skills:intent-reviewer | — (reads the intent from the context file) |
| integration | agent-skills:integration-reviewer | — |
| tests | agent-skills:test-reviewer | — |
| slop | agent-skills:comment-reviewer | — |
| cleanup | agent-skills:cleanup-reviewer | — |
| requirements | agent-skills:requirements-reviewer | the best requirements source, named |
| root-cause | agent-skills:root-cause-reviewer | — |
| premise | agent-skills:premise-reviewer | the behavior the fix changes |
| behavior | agent-skills:behavior-reviewer | — |

## Matrix

| mode | type | scale | passes | mutants |
| --- | --- | --- | --- | --- |
| self | feature | full | general scope intent integration tests slop cleanup requirements | 15 |
| self | feature | lite | general+scope+intent+integration+reuse tests slop:sonnet requirements | 15 |
| self | feature | trivial | general+scope+intent+integration+tests+slop requirements | 15 |
| self | fix | full | pre:premise general+scope+intent+integration tests slop root-cause | 5 |
| self | fix | lite | pre:premise general+scope+intent+integration tests slop root-cause | 5 |
| self | fix | trivial | pre:premise general+scope+intent+integration+tests+slop root-cause | 5 |
| self | refactor | full | general scope integration tests slop cleanup behavior | 10 |
| self | refactor | lite | general+scope+integration+reuse tests slop:sonnet behavior | 10 |
| self | refactor | trivial | general+integration+tests+slop behavior | 10 |
| self | chore | full | general integration tests slop | 0 |
| self | chore | lite | general+integration tests slop:sonnet | 0 |
| self | chore | trivial | general+integration+tests+slop | 0 |
| pr | feature | any | general tests slop integration? requirements scope | 0 |
| pr | fix | any | general tests slop integration? premise | 0 |
| pr | refactor | any | general tests slop integration? behavior | 0 |
| pr | chore | any | general tests slop integration? | 0 |
| pr | undetermined | any | general tests slop integration? | 0 |

The scale tier caps the budget on top of the row: **trivial 3 · lite 8 · full uncapped**.
The plan script prints the capped number, so `mutants` above is the type's budget, not
the effective one. `arch` mode has no breadth passes — its lens trio comes from
`skills/arch-review/SKILL.md`.

## Why the tiers look like this

- A dropped pass never drops its **question** — it folds into general. What no tier
  drops is the type's defining pass: requirements on a feature, premise and root-cause
  on a fix, behavior preservation on a refactor.
- `fix` is identical at lite and full: five agents is already the lean pipeline, and the
  premise pass is at its most valuable on a tiny fix — a flipped guard is exactly where a
  recorded decision hides.
- The cleanup pass runs only at full; at lite its highest-value question (`reuse`) folds
  into general and the rest are C nits with no surface on a small diff.
