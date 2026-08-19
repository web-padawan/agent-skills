# Stage 5 — Report & verdict

## End-state checks

Three assertions, together proving the working tree, the index and `HEAD` are all exactly as found:

- `git rev-parse HEAD` == `<HEAD0>` from stage 0 — nothing was committed.
- `git diff --name-only` empty — nothing unstaged, no mutant residue.
- `git diff --staged --name-only` empty — nothing was staged.

If any of the three differs, say so loudly at the top of the chat reply before anything else.

Pre-existing untracked files are untouched and unstaged. Never commit, amend, push, `git add`, `stash`, `reset --hard`, or `git clean`.

## Report — stage-0 report location (`.omc/self-review/<slug>-FINDINGS.md` in web-components; `<slug>` per stage 0, `/` → `-`)

Write it only when the gate approved Q1. When it did not, put the same content in the chat reply instead, compressed — the findings are never lost, only relocated.

````markdown
# Self-review: <branch> — <date>

**Verdict: ready for PR | needs more work**
Type: <feature | fix | refactor | chore> (signal: <what decided it>)
Premise: <sound | contradicted | unverified> — <citation>   <!-- fix only -->
Deep review: <N> of <M> significant changes   <!-- only when --deep ran -->
Passes: <pass name> ✅ · <pass name> ✅ · <pass name> ⚠️ self-run · <pass name> ❌ missing   <!-- name every pass; "4/5 delivered" hides which one was lost -->

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

- Every finding from every stage appears under its category, tagged `[tier]` and `[status]`. Statuses are exactly two: `confirmed` (real, and still open — this skill fixed nothing) and `accepted` (no action needed — false positive or deliberate choice).
- **Only when `--deep` ran**: add a `## Deep review` section after the summary paragraph, per arch-review's report rules — the three narrative blocks per change **verbatim**, in inventory rank order, with the `[3-lens]` / `[2-lens]` markers from triage; their rolled-up finding lines also appear under `architecture`, `boundary` / `api` and `impact` category headings. Follow it with `## Not deep-reviewed`, listing every significant change that ranked below the `--deep` budget line. Without `--deep`, neither section appears — the Next-steps handoff line is the deep-review pointer.
- Add the profile's own sections after the shared ones: **feature** → `## Requirements coverage`; **fix** → `## Premise & history` first, then `## Root cause & blast radius`; **refactor** → `## Behavior preservation`.
- A **fix** stopped by a contradicted premise gets the short report: the premise line, the `## Premise & history` section with the citation and what the project decided, the size check, and nothing else. The premise-stop `AskUserQuestion` stands in for the stage-3 gate here (see `fix-profile.md`) — write the file only when it approved a report, otherwise the same content goes in the chat reply. Say plainly that stages 1–4 did not run and why — a report that looks thin for that reason is correct, and padding it with findings about code the answer may delete is the failure this stage exists to avoid.
- Omit sections whose agent the profile did not run. Empty category → `- none`.
- Distinguish "not run" from "ran and lost". Tag findings from a `self-run` pass `[self-run]` after the status, and head that category with `> pass self-run — no independent agent review`. A `missing` category reads `- none delivered — pass not covered`, never `- none`.
- Coverage stats line under **Tests**: `N mutants, K killed, S survived, skipped: <hunks or none>`. On a **fix**, prefix it with the whole-fix revert result: `regression test: <name> fails without the fix | none fails without the fix`.
- **Follow-ups** repeats every `confirmed` B and C finding as a paste-ready list for the follow-up issue or PR. A findings are not follow-ups — they are in the way of the merge and belong in `## Next steps`.
- The report itself is never committed — it lives in the git-ignored stage-0 location.

## Verdict rubric

**needs more work** when any of:

- any **confirmed A** finding exists — this skill changes nothing, so an A is unresolved by definition
- **fix**: `premise: contradicted` — the project already decided this behavior differently, so the diff is answering the wrong question; the run stopped before stages 1–4
- **fix**: no test fails when the whole fix is reverted
- **feature**: a stated requirement is unimplemented
- **refactor**: an observable behavior change is unexplained
- a **profile-specific pass** — the bolded one in the stage-0 profile table — is `missing`: the type's defining risk went unexamined, so there is no basis for a verdict

Otherwise **ready for PR**. Confirmed B and C findings never block; they live under Follow-ups.

The verdict describes `HEAD` as it stands. Nothing was changed to reach it.

## Chat reply

Verdict + detected type and profile + tier counts + 3–5 essential bullets + "nothing was changed" + report path. Name every confirmed A finding explicitly — those are what the verdict rests on. Do not restate the full report.

State the pass tally whenever any pass was `self-run` or `missing`. Reduced coverage changes what the verdict is worth, and leaving it out makes the review look stronger than it was.
