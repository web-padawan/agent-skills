# Review profiles — the single source

Two tables. Everything else in this plugin reads them from here, and
`scripts/review-plan.sh` parses them so no skill has to join them by hand.

- **Passes** — the pass id, the agent that runs it, which prepared patch it
  reads, and what its prompt must add beyond the context file path and the
  delivery clause. Every other contract (questions, category, output format,
  verification rules) lives in the agent definition at `agents/<name>.md`.
- **Matrix** — for a mode, change type and scale tier: which passes run, and the
  mutant budget. The plan script resolves a row into a launch list.

## Passes

The `reads` column is the pass's **whole diff input**: `prod` = the prepared
production patch, `tests` = the prepared test patch, `both` = both,
`prod+comments` = the production patch plus the plan's `comment_files`, diffed
directly. A pass never reads a patch outside its lane, and never regenerates one
with `git diff` (pipeline.md §3, *Read discipline*).

| id | agent | reads | prompt adds |
| --- | --- | --- | --- |
| code | agent-skills:code-reviewer | prod+comments | the change type; the plan's `type_conflict` line, when it is not `none`; in `pr` mode, `no reuse/maintainability nits` — both need the author's judgment and a local checkout, so they stay in `self` |
| tests | agent-skills:test-reviewer | both | — |

## Matrix

| mode | type | scale | passes | mutants |
| --- | --- | --- | --- | --- |
| self | feature | any | code tests | 15 |
| self | fix | any | code tests | 5 |
| self | refactor | any | code tests | 10 |
| self | chore | any | code tests | 0 |
| pr | feature | any | code tests | 0 |
| pr | fix | any | code tests | 0 |
| pr | refactor | any | code tests | 0 |
| pr | chore | any | code tests | 0 |
| pr | undetermined | any | code tests | 0 |

The scale tier caps the budget on top of the row: **trivial 3 · lite 8 · full uncapped**.
The plan script prints the capped number, so `mutants` above is the type's budget, not
the effective one. `arch` mode has no breadth passes — its lens trio comes from
`skills/arch-review/SKILL.md`.

## Why the tables look like this

- **Two lanes, two passes.** Production code and tests are the two read lanes a branch has,
  and each lane has exactly one owner. Every extra pass re-read a lane someone else already
  owned, so the branch's lines were paid for once per pass and the overlap was deduped at
  triage — after the spend, not instead of it.
- **The change type is a prompt add, not a pass.** The fix, requirements and behavior passes
  each asked one type's question against the production patch the code pass already reads.
  As checklist sections in that pass they cost no agent and no extra read, and no tier can
  drop them.
- **Scale sizes the mutant budget and nothing else** — trivial 3 · lite 8 · full uncapped.
  It no longer changes the pass list: with two passes covering two lanes there is nothing
  left to drop, and the tier still appears in the plan and the report because it is what the
  coverage stage is sized by.
