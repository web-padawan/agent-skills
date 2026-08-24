# Review profiles — the single source

Two tables. Everything else in this plugin reads them from here, and
`scripts/review-plan.sh` parses them so no skill has to join them by hand.

- **Passes** — the pass id, the agent that runs it, which prepared patch it
  reads, and what its prompt must add beyond the context file path and the
  delivery clause. Every other contract (questions, category, output format,
  verification rules) lives in the agent definition at `agents/<name>.md`.
- **Matrix** — for a mode, change type and scale tier: which passes run, and the
  mutant budget. The plan script resolves a row into a launch list.

Pass token syntax, used in the matrix `passes` column:

- `general+framing` — the pass runs and **folds** the listed passes' core questions
  into itself; findings still go under their own category. Fold ids are pass ids.
- `pre:premise` — launched **alone, before** the rest of the batch; the batch waits
  for its verdict.
- `slop:sonnet` — launch this pass with `model: sonnet`. Judgment passes always keep
  the session default.
- `conformance?` — run only when the repo has a conventions doc.

## Passes

The `reads` column is the pass's **whole diff input**: `prod` = the prepared
production patch, `tests` = the prepared test patch, `both` = both, `comments` =
neither patch, only the plan's `comment_files` diffed directly. A pass never reads a patch outside its lane, and
never regenerates one with `git diff` (pipeline.md §3, *Read discipline*).

| id | agent | reads | prompt adds |
| --- | --- | --- | --- |
| general | agent-skills:general-reviewer | prod | the plan's `folds` list, when it is not `-`; on a fix also name the repo's conventions doc |
| framing | agent-skills:framing-reviewer | prod | the plan's `type_conflict` line, when it is not `none` |
| conformance | agent-skills:conformance-reviewer | prod | in `pr` mode, `conventions half only` — cleanup needs the author's judgment and a local checkout, so it stays in `self` |
| tests | agent-skills:test-reviewer | tests | — |
| slop | agent-skills:comment-reviewer | comments | the plan's `comment_files` list |
| requirements | agent-skills:requirements-reviewer | both | the best requirements source, named |
| root-cause | agent-skills:root-cause-reviewer | both | — |
| premise | agent-skills:premise-reviewer | prod | the behavior the fix changes |
| behavior | agent-skills:behavior-reviewer | both | — |

## Matrix

| mode | type | scale | passes | mutants |
| --- | --- | --- | --- | --- |
| self | feature | full | general framing conformance tests slop requirements | 15 |
| self | feature | lite | general+framing+conformance tests slop:sonnet requirements | 15 |
| self | feature | trivial | general+framing+conformance+tests+slop requirements | 15 |
| self | fix | full | pre:premise general+framing+conformance tests slop root-cause | 5 |
| self | fix | lite | pre:premise general+framing+conformance tests slop root-cause | 5 |
| self | fix | trivial | pre:premise general+framing+conformance+tests+slop root-cause | 5 |
| self | refactor | full | general framing conformance tests slop behavior | 10 |
| self | refactor | lite | general+framing+conformance tests slop:sonnet behavior | 10 |
| self | refactor | trivial | general+framing+conformance+tests+slop behavior | 10 |
| self | chore | full | general conformance tests slop | 0 |
| self | chore | lite | general+conformance tests slop:sonnet | 0 |
| self | chore | trivial | general+conformance+tests+slop | 0 |
| pr | feature | any | general tests slop conformance? requirements framing | 0 |
| pr | fix | any | general tests slop conformance? premise | 0 |
| pr | refactor | any | general tests slop conformance? behavior | 0 |
| pr | chore | any | general tests slop conformance? | 0 |
| pr | undetermined | any | general tests slop conformance? | 0 |

The scale tier caps the budget on top of the row: **trivial 3 · lite 8 · full uncapped**.
The plan script prints the capped number, so `mutants` above is the type's budget, not
the effective one. `arch` mode has no breadth passes — its lens trio comes from
`skills/arch-review/SKILL.md`.

## Why the tiers look like this

- A dropped pass never drops its **question** — it folds into general. What no tier
  drops is the type's defining pass: requirements on a feature, premise and root-cause
  on a fix, behavior preservation on a refactor.
- `framing` and `conformance` each carry two questions because each pair shares its
  inputs, not because the questions are the same. Framing reads only the intent line,
  the declared type and the prod patch, and answers both "does this match the goal it
  states" and "does this match the boundary it claims". Conformance answers "do the
  siblings already do it this way" and "does that helper already exist" from **one**
  sibling sweep — the most expensive thing either half does, and it used to run twice.
  Findings still go under `intent` / `scope` and `integration` / `cleanup`.
- `intent` and `requirements` overlap on a feature — requirements asks intent's question
  once per requirement, against the same source — but only where that source is
  enumerable. When the whole intent is a one-line PR body there is nothing to enumerate,
  which is the case framing's drift half still earns.
- `fix` is identical at lite and full: five agents is already the lean pipeline, and the
  premise pass is at its most valuable on a tiny fix — a flipped guard is exactly where a
  recorded decision hides.
- Cleanup reaches every **self** tier now that it shares the conformance sweep, where it
  used to run standalone at full and fold as `reuse` at lite. It costs no agent and no
  extra read, and `rationale.md` is explicit that C findings are the point of a local
  review. In `pr` mode conformance runs its conventions half alone: a cleanup finding
  there is a comment asking someone else to make a judgment call the author already
  made.
- Lanes, not pass count, are what a profile pays for. Tests are usually most of a
  branch's changed lines, so passes each reading the whole diff paid for the test hunks
  once per pass to review them once. Only `requirements`, `root-cause` and `behavior`
  have a question that spans both lanes.
- The largest profile is six agents (`feature/full`), which is the batch cap
  `rationale.md` sets. It was eight.
