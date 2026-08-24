# Gate, report, verdict

## The gate (step 6)

First in chat, compact and scannable — the full detail belongs in the report:

```
Type: refactor — signal: branch name prefix · Scale: lite (78 lines, 4 files)
Premise: sound — #9239 review kept the filter guard   (fix only)

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
Premise: <sound | contradicted | unverified> — <citation>   <!-- fix only -->
Deep review: <N> of <M> significant changes   <!-- only when --deep ran -->
Passes: <pass name> ✅ · <pass name> ⚠️ self-run · <pass name> ❌ missing   <!-- name every pass -->

**Nothing was changed** — this report is the only output.

| Tier            | Confirmed | Accepted |
| --------------- | --------- | -------- |
| A critical      |           |          |
| B follow-up     |           |          |
| C taste         |           |          |

<one paragraph: what was reviewed, what was found, what remains>

## General review
- [A][confirmed] packages/foo/src/foo.js:42 — <claim> → <suggested fix>
- [C][accepted] <file>:<line> — <claim> — <why it is not a problem>

## Scope
## Intent
## Integration
## Tests
## Slop
## Cleanup

## Follow-ups
- [B] <file>:<line> — <claim> → <suggested fix>

## Next steps
Fix the A findings, then re-run. Coverage gaps: `/agent-skills:mutation-coverage <file>`.
For architectural/boundary/impact analysis of a specific change, run `/agent-skills:arch-review <file>:<lines>`.
````

- Every finding appears under its category, tagged `[tier]` and `[status]`. Statuses are
  exactly two: `confirmed` (real, still open — this skill fixed nothing) and `accepted` (no
  action needed — false positive or deliberate choice).
- Add the profile's own sections after the shared ones: **feature** → `## Requirements
  coverage`; **fix** → `## Premise & history` first, then `## Root cause & blast radius`;
  **refactor** → `## Behavior preservation`. Omit sections whose pass did not run; an empty
  category reads `- none`.
- **Only when `--deep` ran**: a `## Deep review` section and a `## Not deep-reviewed` list,
  both exactly as [`../../arch-review/SKILL.md`](../../arch-review/SKILL.md) step 4 defines
  them — its rules are the single source, do not restate them. Without `--deep`, the Next
  steps line is the deep-review pointer.
- Distinguish "not run" from "ran and lost". Tag `self-run` findings `[self-run]` after the
  status and head that category with `> pass self-run — no independent agent review`. A
  `missing` category reads `- none delivered — pass not covered`, never `- none`.
- Coverage stats line under **Tests**: `N mutants, K killed, S survived, skipped: <hunks or
  none>`. On a **fix**, prefix it with the whole-fix revert result: `regression test: <name>
  fails without the fix | none fails without the fix`.
- **Follow-ups** repeats every `confirmed` B and C finding as a paste-ready list for the
  follow-up issue. A findings are not follow-ups — they are in the way of the merge and
  belong in `## Next steps`.
- On a **fix** with `premise: contradicted`, the `## Premise & history` section leads the
  report: the citation, what the project decided, and what the fix does instead — the top A
  finding the verdict rests on.
- The report is never committed — it lives in the git-ignored path the plan named.

## Verdict rubric

**needs more work** when any of:

- any **confirmed A** finding exists — this skill changes nothing, so an A is unresolved by
  definition
- **fix**: `premise: contradicted`, or no test fails when the whole fix is reverted
- **feature**: a stated requirement is unimplemented
- **refactor**: an observable behavior change is unexplained
- the type's **defining pass** (requirements on a feature, the fix pass on a fix,
  behavior preservation on a refactor) is `missing`: the type's defining risk went
  unexamined, so there is no basis for a verdict

Otherwise **ready for PR**. Confirmed B and C findings never block; they live under
Follow-ups. The verdict describes `HEAD` as it stands — nothing was changed to reach it.

## Chat reply

Verdict + type and scale + tier counts + 3–5 essential bullets + "nothing was changed" +
report path. Name every confirmed A finding explicitly — those are what the verdict rests on.
State the pass tally whenever any pass was `self-run` or `missing`: reduced coverage changes
what the verdict is worth, and leaving it out makes the review look stronger than it was.
