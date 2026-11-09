# Gate, report, verdict

## The gate (step 6)

Render the gate from the frozen list of triage
([`../../../references/pipeline.md`](../../../references/pipeline.md) §5.7), never from the
agent reports.

First, print this in chat, compact and scannable. The full detail belongs in the report:

```
Type: refactor — signal: branch name prefix · Scale: lite (78 lines, 4 files)

A (must fix before merge) — 2
  packages/foo/src/foo.js:42 — <claim> → <suggested fix>
B (follow-up is fine) — 3
C (taste) — 5
```

**Whenever there is at least one A, say this before the questions:** this skill applies
nothing, so nothing can clear an A finding inside a run. The verdict will be *needs more work*
whatever the user chooses here.

Then ask a single `AskUserQuestion` with two questions:

**Q1, header `Report`**: "Write the findings report?"
- `Yes — write FINDINGS.md` *(Recommended)*. Name the `report:` path from the plan in the
  description.
- `No — chat summary only`

On the **trivial** tier with zero A findings, swap the recommendation to
`No — chat summary only`. A report file for a nit-only review of a 10-line diff is ceremony.

**Q2, header `Coverage`**: "Run the coverage check? It temporarily mutates source lines and
restores each one."
- `Yes — run it` *(Recommended)* · `Skip it`

When the plan prints `mutant_pool: 0`, swap the recommendation to `Skip it`
(description: the prod diff has no mutable source lines). Still offer the run, because the
pool is a heuristic.

Rules:

- A custom answer ("Other") wins over the presets. Do exactly what it names.
- Drop nothing either way. `No — chat summary only` relocates the findings and does not
  delete them.
- When there is nothing to report (no findings, or only `accepted` ones), ask Q2 alone. When
  the mutant budget is 0 (chore, or `--no-coverage`), ask Q1 alone.
- On a **fix**, say that the coverage skip also skips the whole-fix revert. That revert is
  the one check that a bug fix most needs, because it proves that a regression test exists.

## End-state checks (step 8)

Make three assertions. Together they prove that the working tree, the index and `HEAD` are
exactly as you found them:

- `git rev-parse HEAD` == `head0` from the plan, which shows that no commit happened.
- `git diff --name-only` empty, which shows that nothing is unstaged and no mutant residue
  remains.
- `git diff --staged --name-only` empty, which shows that nothing is staged.

If any assertion fails, say so loudly at the top of the chat reply, before anything else.
Pre-existing untracked files stay untouched and unstaged.

## Report — at the plan's `report:` path

Write the report only when the gate approved Q1. Otherwise, put the same content in the chat
reply, compressed. Never lose a finding, only relocate it.

````markdown
# Self-review: <branch> — <date>

**Verdict: ready for PR | needs more work**
Type: <feature | fix | refactor | chore> (signal: <what decided it>)
Scale: <trivial | lite | full> (<N> lines, <M> files<, override reason>)
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

## Earlier findings   <!-- omit when the plan printed earlier_findings: none -->
| Id | Status | Finding |
| --- | --- | --- |
| F3 | fixed | packages/foo/src/foo.js:42 — <claim> |

## Follow-ups
- [B] <file>:<line> — **<label> (<category>, non-blocking):** <one-line claim>

## Next steps
Fix the A findings, then re-run. Coverage gaps: write the test that each survivor names.
````

- Every finding appears under its category, tagged `[tier]` and `[status]`. Statuses are
  exactly two. `confirmed` means real and still open, because this skill fixed nothing.
  `accepted` means that the finding needs no action, as a false positive or a deliberate
  choice. Add `[orchestrator]` to findings that you raised yourself rather than a pass.
- **When the verification of a claim is not obvious from the claim, say how you verified
  it.** Close the finding with `— verified: <how>` (the command run, the browsers reproduced
  in, the commit read). A corrected agent claim says what the agent overstated, in one clause.
- Write one section per category that the `change`, `code` and `tests` passes report, in the
  order above. The category list is in
  [`../../../references/pipeline.md`](../../../references/pipeline.md) §3. The `api` findings
  file goes under **Boundary**. Omit the `## Fix` section on a change that is not a fix. An
  empty category reads `- none`.
- **Deep review** holds the blocks of the change pass, in the rank order of that pass. Scale
  the prose to the finding so that the report stays readable at any budget. An **A-tier**
  change keeps its block in full, close to verbatim. A **B/C-only** change keeps one condensed
  line (`Promise` + `Before merge`), because the finding lines already carry the claim. A
  **clean** change keeps `NO FINDINGS` plus its `Boundary` and `Consumers` lines, so that the
  clean verdict is on the record.
- **Not deep-reviewed** lists every `BELOW LINE` candidate with its reason. Never drop a
  candidate silently. Omit both sections when the deep budget was 0 or the pass returned
  `NO SIGNIFICANT CHANGES`. Say which reason applies.
- Distinguish "not run" from "ran and lost". Tag `self-run` findings `[self-run]` after the
  status. Head that category with `> pass self-run — no independent agent review`. A
  `missing` category reads `- none delivered — pass not covered`, never `- none`.
- Put the coverage stats line under **Tests**:
  `N mutants, K killed, S survived, skipped: <hunks or none>`. On a **fix**, prefix it with
  the whole-fix revert result:
  `regression test: <name> fails without the fix | none fails without the fix`.
- **Follow-ups** indexes every `confirmed` B and C finding as a paste-ready list for the
  follow-up issue. Each line holds `file:line`, the Conventional Comments label and
  decorations of the finding from the frozen list
  ([`../../../references/severity.md`](../../../references/severity.md), *Rendering*), and
  the one-line claim. Do not include the fix, because it is above, under its category. When
  you paste the list into an issue, each line already reads as a review comment. A findings
  are not follow-ups. They belong in `## Next steps`.
- On a **fix**, a finding that the change reverses a behavior that an existing test asserts
  on purpose leads the report. That finding questions the diff, not a line of it.
- **Earlier findings** lists every finding of the findings file that the plan read, with
  the status that triage applied. A finding that stays open also appears under its category.
- Never commit the report. It lives in the git directory, at the path that the plan named.

## Findings file — at the plan's `findings_file:` path

The next run of this skill starts from this file. It is also the record of the review: the
head that the run reviewed, and its verdict. The plan script reads it with `jq`. Write it
with Write as one JSON object:

```json
{
  "schema": 1,
  "branch": "feat/foo",
  "head": "<the head SHA of this run>",
  "base": "<the base SHA of this run>",
  "date": "2026-11-02",
  "round": 2,
  "verdict": "ready for PR",
  "findings": [
    {
      "id": "F1",
      "round": 1,
      "category": "tests",
      "tier": "B",
      "status": "open",
      "file": "packages/foo/src/foo.js",
      "line": 42,
      "claim": "<the frozen claim>",
      "fix": "<the one-line fix>",
      "verified": "<how, when not obvious>",
      "merged": [
        { "file": "packages/foo/src/foo.js", "line": 40, "claim": "<a claim merged into this one>" }
      ]
    }
  ]
}
```

- `schema` is the version of this format. Write `1`. The plan reads a file without
  `schema` as schema 1, and does not read a file of a higher schema.
- Write the file at the end of every run, also when the review has no finding. Then
  `findings` is `[]`, which records a clean review of `head`.
- `round` at the top is the number of the last round of this run. Each finding keeps the
  round that found it.
- `verdict` is the verdict of the run, per the verdict rubric: `ready for PR` or
  `needs more work`. Omit it when you write the file between rounds. A file without
  `verdict` is the record of a run that did not finish.
- Keep every finding of the earlier file, with its new status. Give a new finding the next
  free id. Never reuse an id.
- When triage merges a finding into another one (pipeline.md §5.2), add it to the `merged`
  list of the kept finding. Give each entry its `file`, `line` and `claim`. The plan lists
  the entries with the kept finding, so a later round does not report them again. Example:
  triage merged a docblock claim at `:441` into a finding at `:446` and left it out of the
  file. The next round reported it again.
- `status` is one of these values:
  - `open`: real and not fixed. Every new `confirmed` finding starts here.
  - `accepted`: needs no action, a false positive or a deliberate choice.
  - `fixed`, `partially_fixed`, `fixed_wrongly`, `not_fixed`, `obsolete`: from an `earlier`
    line of a pass.
  - `disputed`: the author says that the code is correct. No later run reports it again.
- When the author disputes a finding at the gate, by id or by claim, set it to `disputed`.
  The author can also edit the file by hand between runs.

## Earlier findings and the verdict

An earlier A finding with status `open`, `not_fixed`, `partially_fixed` or `fixed_wrongly`
counts as a confirmed A. A `not checked` earlier finding keeps its status, and the report
says that no pass checked it.

## Verdict rubric

**needs more work** when any of:

- any **confirmed A** finding exists. This skill changes nothing, so an A is unresolved by
  definition.
- **fix**: no test fails when you revert the whole fix
- **feature**: a stated requirement is unimplemented
- **refactor**: an observable behavior change is unexplained
- the `change` or `code` pass is `missing`. Then what the change does, or how the diff reads,
  went unexamined, so there is no basis for a verdict.

Otherwise **ready for PR**. Confirmed B and C findings never block. They live under
Follow-ups. The verdict describes `HEAD` as it stands. You changed nothing to reach it.

## Chat reply

Give the verdict, the type and scale, the tier counts, 3 to 5 essential bullets,
"nothing was changed", and the report path. Name every confirmed A finding explicitly, because
the verdict rests on those. State the pass tally whenever any pass was `self-run` or
`missing`. Reduced coverage changes what the verdict is worth. A reply without the tally makes
the review look stronger than it was.
