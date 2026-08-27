# Gate, report, verdict

## The gate (step 6)

Render this from triage's frozen list ([`../../../references/pipeline.md`](../../../references/pipeline.md)
§5.6) — never by re-reading the agent reports. The tier counts shown here are the counts the
report will carry; if they disagree, the gate was built from something other than the list.

First in chat, compact and scannable — the full detail belongs in the report:

```
Type: refactor — signal: branch name prefix · Scale: lite (78 lines, 4 files)

A (must fix before merge) — 2
  packages/foo/src/foo.js:42 — <claim> → <suggested fix>
B (follow-up is fine) — 3
C (taste) — 5
```

**Say this before asking, whenever there is at least one A:** this skill applies nothing, so
an A finding cannot be cleared inside a run — the verdict will be *needs more work* whatever
is chosen here.

Then a single `AskUserQuestion` with two questions:

**Q1 — header `Report`**: "Write the findings report?"
- `Yes — write FINDINGS.md` *(Recommended)* — name the plan's `report:` path in the description
- `No — chat summary only`

On the **trivial** tier with zero A findings, swap the recommendation to `No — chat summary
only`: a report file for a nit-only review of a 10-line diff is ceremony.

**Q2 — header `Coverage`**: "Run the coverage check? It temporarily mutates source lines and
restores each one."
- `Yes — run it` *(Recommended)* · `Skip it`

When the plan prints `mutant_pool: 0`, swap the recommendation to `Skip it` and say why in the
description: the budget comes from the type × scale matrix, which is blind to what the diff is
made of, and a diff that is all CSS, CSS-in-JS or markup holds nothing
[`mutation.md`](mutation.md) would accept as a candidate. Still offer the run — the pool is a
heuristic, and the author may know a mutable line it missed.

Rules:

- A custom answer ("Other") wins over the presets — do exactly what it names.
- Nothing is dropped either way: `No — chat summary only` relocates the findings, it does not
  delete them.
- Nothing to report (no findings, or only `accepted` ones) → ask Q2 alone. Mutant budget 0
  (chore, or `--no-coverage`) → ask Q1 alone.
- On a **fix**, say that skipping coverage also skips the whole-fix revert — the one check a
  bug fix most needs, since it is what proves a regression test exists.

## End-state checks (step 8)

Three assertions, together proving the working tree, the index and `HEAD` are exactly as found:

- `git rev-parse HEAD` == the plan's `head0` — nothing was committed.
- `git diff --name-only` empty — nothing unstaged, no mutant residue.
- `git diff --staged --name-only` empty — nothing was staged.

If any differs, say so loudly at the top of the chat reply before anything else. Pre-existing
untracked files are untouched and unstaged.

## Report — at the plan's `report:` path

Write it only when the gate approved Q1. Otherwise the same content goes in the chat reply,
compressed — the findings are never lost, only relocated.

````markdown
# Self-review: <branch> — <date>

**Verdict: ready for PR | needs more work**
Type: <feature | fix | refactor | chore> (signal: <what decided it>)
Scale: <trivial | lite | full> (<N> lines, <M> files<, override or --scale reason>)
Deep review: <N> of <M> significant changes   <!-- omit when the deep budget was 0 -->
Passes: <pass name> ✅ · <pass name> ⚠️ self-run · <pass name> ❌ missing   <!-- name every pass -->

**Nothing was changed** — this report is the only output.

| Tier            | Confirmed | Accepted |
| --------------- | --------- | -------- |
| A critical      |           |          |
| B follow-up     |           |          |
| C taste         |           |          |

<one paragraph: what was reviewed, what was found, what remains>

## Scope
- [A][confirmed] packages/foo/src/foo.js:42 — <claim> → <suggested fix>
- [C][accepted] <file>:<line> — <claim> — <why it is not a problem>

## Behavior
## Fix
## Boundary
## Impact
## Logic
## Conventions
## Reuse
## Maintainability
## Comments
## Tests

## Deep review
### <file>:<line-range> — <short name>   <!-- one per block the change pass returned -->
<block prose, scaled to the finding — see below>

## Not deep-reviewed
- <file>:<line-range> — <reason it ranked below the line, or `covered by <block name>`>

## Follow-ups
- [B] <file>:<line> — <one-line claim>

## Next steps
Fix the A findings, then re-run. Coverage gaps: `/agent-skills:mutation-coverage <file>`.
````

- Every finding appears under its category, tagged `[tier]` and `[status]`. Statuses are
  exactly two: `confirmed` (real, still open — this skill fixed nothing) and `accepted` (no
  action needed — false positive or deliberate choice). Add `[orchestrator]` to findings you
  raised yourself rather than a pass.
- **Say how a claim was verified when it is not obvious from the claim.** Close the finding
  with `— verified: <how>`: the command you ran, the browsers you reproduced in, the commit
  you read. [`../../../references/delivery.md`](../../../references/delivery.md) has you
  pre-verifying during the wait precisely so `confirmed` means something; a report that never
  says how is indistinguishable from one that took the agents at their word. Corrections to an
  agent's wording get the same treatment — say what was overstated, in one clause.
- One section per category the `change`, `code` and `tests` passes report, in the order
  above; the category list is [`../../../references/pipeline.md`](../../../references/pipeline.md)
  §3's (`api` findings file under **Boundary**). Omit the `## Fix` section on a change that is
  not a fix; an empty category reads `- none`.
- **Deep review** holds the change pass's blocks, in its rank order, with the prose scaled to
  the finding so the report stays readable at any budget: an **A-tier** change keeps its block
  in full, close to verbatim; a **B/C-only** change keeps one condensed line (`Promise` +
  `Before merge`) — the finding lines already carry the claim; a **clean** change keeps
  `NO FINDINGS` plus its `Boundary` and `Consumers` lines, so the clean verdict is on the
  record. **Not deep-reviewed** lists every `BELOW LINE` candidate with its reason — never
  silently dropped. Omit both sections when the deep budget was 0 or the pass returned
  `NO SIGNIFICANT CHANGES` (say which).
- Distinguish "not run" from "ran and lost". Tag `self-run` findings `[self-run]` after the
  status and head that category with `> pass self-run — no independent agent review`. A
  `missing` category reads `- none delivered — pass not covered`, never `- none`.
- Coverage stats line under **Tests**: `N mutants, K killed, S survived, skipped: <hunks or
  none>`. On a **fix**, prefix it with the whole-fix revert result: `regression test: <name>
  fails without the fix | none fails without the fix`.
- **Follow-ups** indexes every `confirmed` B and C finding as a paste-ready list for the
  follow-up issue: `file:line` plus the claim compressed to one line, and **not** the suggested
  fix — that is three lines above under its category, and repeating it turns a third of the
  report into a second copy of itself. A findings are not follow-ups — they are in the way of
  the merge and belong in `## Next steps`.
- On a **fix**, a finding that the change reverses a behavior an existing test asserts on
  purpose leads the report: it questions the diff, not a line of it.
- The report is never committed — it lives in the git-ignored path the plan named.

## Verdict rubric

**needs more work** when any of:

- any **confirmed A** finding exists — this skill changes nothing, so an A is unresolved by
  definition
- **fix**: no test fails when the whole fix is reverted
- **feature**: a stated requirement is unimplemented
- **refactor**: an observable behavior change is unexplained
- the `change` or `code` pass is `missing`: what the change does, or how it is written, went
  unexamined, so there is no basis for a verdict

Otherwise **ready for PR**. Confirmed B and C findings never block; they live under
Follow-ups. The verdict describes `HEAD` as it stands — nothing was changed to reach it.

## Chat reply

Verdict + type and scale + tier counts + 3–5 essential bullets + "nothing was changed" +
report path. Name every confirmed A finding explicitly — those are what the verdict rests on.
State the pass tally whenever any pass was `self-run` or `missing`: reduced coverage changes
what the verdict is worth, and leaving it out makes the review look stronger than it was.
