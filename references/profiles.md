# Review profiles — the single source

The tables below are the single source. Everything else in this plugin reads them from here.
`scripts/review-plan.sh` parses them, so no skill has to join them by hand.

- **Passes**. The pass id, the agent that runs it, the prepared patch that it reads, and
  what its prompt adds. The prompt adds come on top of the context file path and the
  delivery clause. The script resolves that column into the literal prompt that it prints
  under `=== PROMPTS ===`. Every other contract (questions, category, output format,
  verification rules) lives in the agent definition at `agents/<name>.md`.
- **Matrix**. For a mode, change type and scale tier, the passes that run and the mutant
  budget. The plan script resolves a row into a launch list.
- **Pass effort** and **Pass model**. What the scale tier caps per pass, and the model that
  runs each pass.

## Passes

The `reads` column is the **whole diff input** of the pass. `prod` is the prepared
production patch. `tests` is the prepared test patch. `both` is both patches.
`prod+comments` is the production patch plus the plan's `comment_files`, diffed directly.

A pass never reads a patch outside its lane. A pass never regenerates a patch with
`git diff` (pipeline.md §2, *Read discipline*).

| id | agent | reads | prompt adds |
| --- | --- | --- | --- |
| change | agent-skills:change-reviewer | prod | the change type; the plan's `type_conflict` line, when it is not `none`; the plan's `deep` budget (`deep budget N`) |
| code | agent-skills:code-reviewer | prod+comments | in `pr` mode, `no reuse/maintainability nits`. Both need the author's judgment and a local checkout, so they stay in `self` |
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

The scale tier caps both budgets on top of the row. Mutants: **trivial 3, lite 8, full
uncapped**. Deep blocks: **trivial 1, lite 2, full uncapped**.

The plan script then caps the deep budget a second time by what the diff offers. It counts
**deep candidates**: `.d.ts` hunks, new exports, and added public (non-underscore) members.
The effective budget is `min(row, tier cap, max(1, candidates))`. So a fix with no public
surface gets one block for its top change instead of three surveys. The plan script prints
the capped numbers and the candidate count.

`--deep N` overrides the deep budget outright. `--deep 0` keeps the change pass but skips
its blocks.

**Production lines** size the scale tier, not the whole branch. Tests never enter the mutant
or deep budgets. A 30-line fix with 80 lines of tests is a lite review.

| scale | production lines | files |
| --- | --- | --- |
| trivial | ≤ 10 | ≤ 2 |
| lite | ≤ 150 | ≤ 8 |
| full | above | above |

Risk overrides (a `.d.ts` change, a new export, CI or release files) force `full` regardless
of size.

## Pass effort

The tier also caps what a single pass may spend, because the deep budget alone does not.

| scale | tool calls per pass | when the ceiling binds |
| --- | --- | --- |
| trivial | ~10 | report what you have |
| lite | ~20 | report what you have |
| full | ~30 | say in the report which checklist sections you could not finish |

These are ceilings, not targets. A pass that answers its checklist in six calls is complete.
A ceiling that a pass never approaches makes it economize on nothing. Each `agents/<name>.md`
names what that pass drops first. The orchestrator passes the tier's ceiling in the prompt,
the same way it passes the deep budget.

Triage gets its own ceiling. To verify findings is not free, and the pass ceilings do not
cover it:

| scale | triage tool calls | spend them on |
| --- | --- | --- |
| trivial | ~5 | the one claim that decides the verdict |
| lite | ~10 | every A candidate, then the B claims a pass marked `unverified` |
| full | ~15 | the same, plus one runtime probe when a claim turns on real browser behavior |

A claim that would cost more than its share stays `unverified` and caps at B (severity.md).
Verification that **runs the thing** beats a second read. A browser probe settles a CSS or
shadow-DOM claim that no amount of re-reading can. Playwright MCP blocks `file:` URLs.
Navigate to `about:blank`. Then build the tree inside `browser_evaluate`.

## Pass model

The tier also picks the model per pass. The change pass carries the boundary and impact
judgment, so it keeps the strongest model at every tier. The code and tests passes run a
checklist over a diff that the skeleton already quotes. Below the full tier, a smaller model
does that equally well.

| scale | change | code | tests |
| --- | --- | --- | --- |
| trivial | opus | sonnet | sonnet |
| lite | opus | sonnet | sonnet |
| full | opus | opus | opus |

The plan prints the model beside each pass and in its `=== PROMPTS ===` header. The
orchestrator passes the model as the Agent tool's `model`. A new pass is a new column.

Why the tables look like this: [`rationale.md`](rationale.md).
