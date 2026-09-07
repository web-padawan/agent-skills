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
with `git diff` (pipeline.md §2, *Read discipline*).

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
uncapped**, deep blocks **trivial 1 · lite 2 · full uncapped**. The deep budget is then capped
a second time by what the diff actually offers: the plan script counts **deep candidates** —
`.d.ts` hunks, new exports, added public (non-underscore) members — and the effective budget
is `min(row, tier cap, max(1, candidates))`, so a fix with no public surface gets one block
for its top change instead of three surveys. The plan script prints the capped numbers and the
candidate count. `--deep N` overrides the deep budget outright; `--deep 0` keeps the change
pass but skips its blocks.

The scale tier is sized by **production lines**, not the whole branch: tests never enter the
mutant or deep budgets, and a 30-line fix with 80 lines of tests is a lite review.

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

These are ceilings, not targets — a pass that answers its checklist in six calls is done,
and a ceiling a pass never approaches makes it economize on nothing. Each `agents/<name>.md` names what that pass drops first. The orchestrator passes the tier's
ceiling in the prompt the same way it passes the deep budget.

Triage gets its own ceiling, because verifying findings is not free and the pass ceilings do
not cover it:

| scale | triage tool calls | spend them on |
| --- | --- | --- |
| trivial | ~5 | the one claim that decides the verdict |
| lite | ~10 | every A candidate, then the B claims a pass marked `unverified` |
| full | ~15 | the same, plus one runtime probe when a claim turns on real browser behavior |

A claim that would cost more than its share stays `unverified` and caps at B (severity.md).
Verifying by **running the thing** beats reading it again: a browser probe settles a CSS or
shadow-DOM claim that no amount of re-reading will. With Playwright MCP, `file:` URLs are
blocked — navigate to `about:blank` and build the tree inside `browser_evaluate`.

## Why the tables look like this

- **Three questions, three passes.** A branch raises three questions — what the change
  *does and promises* (scope, behavior, fix correctness, boundary, impact), how the code is
  *written* (logic, conventions, reuse, maintainability, comments), and whether the *tests*
  pin it. Each question has one owner, so the searches do not repeat: the consumer grep
  belongs to the change pass, the sibling sweep to the code pass, the test patch to the tests
  pass. The **findings** still overlap where one defect answers two questions — a selector
  that is both wrong behavior and a conventions breach reaches `change` and `code` alike. That
  is cross-checking worth paying for, and it is why anchors are pinned to the declaration line
  (pipeline.md §3): matched anchors make the dedup mechanical instead of manual.
- **The change type is a prompt add, not a pass.** The fix, requirements and behavior passes
  each asked one type's question against the production patch. As checklist sections of the
  change pass they cost no agent and no extra read, and the code pass is type-agnostic.
- **Deep review is a budget inside the change pass, not a second stage.** The boundary and
  impact blocks run on the top changes the pass selects itself, in the same barrier as the
  other passes; `deep` sizes how many, the same way `mutants` sizes the coverage stage.
- **Scale sizes budgets, never the pass list** — mutants, deep blocks (further capped by the
  diff's deep candidates), and the per-pass effort ceiling above. With three passes covering three questions there is nothing left to
  drop, so the tier buys smaller passes rather than fewer of them, and it stays in the plan
  and the report because it is what the budgets are sized by.
