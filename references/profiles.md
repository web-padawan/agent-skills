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
| change | agent-skills:change-reviewer | prod | the change type; the plan's `type_conflict` line, when it is not `none`; the plan's `deep` budget (`deep budget N`) |
| code | agent-skills:code-reviewer | prod+comments | in `pr` mode, `no reuse/maintainability nits` — both need the author's judgment and a local checkout, so they stay in `self` |
| tests | agent-skills:test-reviewer | both | — |

## Matrix

| mode | type | scale | passes | mutants | deep |
| --- | --- | --- | --- | --- | --- |
| self | feature | any | change code tests | 15 | 3 |
| self | fix | any | change code tests | 5 | 3 |
| self | refactor | any | change code tests | 10 | 3 |
| self | chore | any | change code tests | 0 | 0 |
| pr | feature | any | change code tests | 0 | 3 |
| pr | fix | any | change code tests | 0 | 3 |
| pr | refactor | any | change code tests | 0 | 3 |
| pr | chore | any | change code tests | 0 | 0 |
| pr | undetermined | any | change code tests | 0 | 3 |

The scale tier caps both budgets on top of the row: mutants **trivial 3 · lite 8 · full
uncapped**, deep blocks **trivial 1 · lite 2 · full uncapped**. The plan script prints the
capped numbers, so `mutants` and `deep` above are the type's budgets, not the effective ones.
`--deep N` overrides the deep budget outright; `--deep 0` keeps the change pass but skips its
blocks.

## Why the tables look like this

- **Three questions, three passes.** A branch raises three questions — what the change
  *does and promises* (scope, behavior, fix correctness, boundary, impact), how the code is
  *written* (logic, conventions, reuse, maintainability, comments), and whether the *tests*
  pin it. Each question has exactly one owner, so no two passes search for the same thing:
  the consumer grep belongs to the change pass, the sibling sweep to the code pass, the test
  patch to the tests pass.
- **The change type is a prompt add, not a pass.** The fix, requirements and behavior passes
  each asked one type's question against the production patch. As checklist sections of the
  change pass they cost no agent and no extra read, and the code pass is type-agnostic.
- **Deep review is a budget inside the change pass, not a second stage.** The boundary and
  impact blocks run on the top changes the pass selects itself, in the same barrier as the
  other passes; `deep` sizes how many, the same way `mutants` sizes the coverage stage.
- **Scale sizes budgets and nothing else** — mutants and deep blocks. It never changes the
  pass list: with three passes covering three questions there is nothing left to drop, and
  the tier still appears in the plan and the report because it is what the budgets are
  sized by.
