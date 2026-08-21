# Stage 4 — Coverage check (report-only)

Purpose: verify the branch's tests pin its invariants. A mutant that survives — tests stay green while the change is broken — is a coverage gap, and here it becomes a **finding**. This skill never writes the missing test. Skip this stage entirely when the gate chose `Skip it`, when `--no-coverage` was passed, or when the profile has no budget (**chore**).

This is the one stage that writes to a tracked file, and it is the skill's only carve-out from the no-edit rule. Every mutant is temporary, restored before the next, and never staged.

## Preconditions

- `git status --porcelain --untracked-files=no` is empty.
- `git rev-parse HEAD` still equals `<HEAD0>` from stage 0.

> Restoring uses `git checkout -- <file>`, which resets the file to the **index**. Because this skill never stages anything, the index equals `HEAD`, so the restore is exact and total. That is the whole safety argument, and it holds only while the tree is clean.

If the tree is dirty at the start of the stage or at any mutant boundary, **stop the stage** and report it as a finding. Do not try to reconcile, do not guess which change was yours, and never reach for `git clean` or `git stash`.

## Mutant selection

Candidates: added/changed source lines in `git diff <BASE>..HEAD` (`<BASE>` = literal SHA from stage 0) — scope it to the repo's source globs, `-- 'packages/*/src/*.js'` in vaadin/web-components. Source only, never tests, never type declarations.

Skip lines that cannot produce a meaningful mutant: imports/exports, CSS/template-literal styling, JSDoc/comments, pure renames, lines whose removal is a syntax error that cannot be isolated.

Prioritize by logic density: conditionals and early returns > event listener add/remove > calculations and assignments > everything else. Weight toward the lines the stage-1 findings already called out — a mutant on a line a pass flagged is worth more than one on an incidental line. List skipped hunks in the report — silent truncation is forbidden.

### Budget and targeting per profile

The scale tier caps every budget below: effective budget = `min(profile budget, cap)` — cap 3 on **trivial**, 8 on **lite**, uncapped on **full**. The fix profile's whole-fix revert runs at every scale.

- **fix — 5 mutants, and the whole-fix revert first.** Before any single-line mutant, revert the entire fix as one unit (`git stash` is forbidden — comment out the changed hunks, or `git checkout <BASE> -- <source file>` when the file's only change is the fix) and run the affected tests. **A new test must fail.** If every test still passes, the branch has no regression test for the bug it claims to fix — that is an A finding, the most important output of this stage. Restore, then spend the 5 mutants inside the fix's own hunks only; unrelated lines are not this branch's job.
- **feature — 15 mutants**, weighted to the feature's new behavior: the new public path first (the property setter, the event dispatch, the guard that makes the feature conditional), then its interaction with existing state (`disabled`, `readonly`, RTL), then everything else.
- **refactor — 10 mutants** on the refactored logic. A refactor with unchanged tests should kill everything; a survivor here usually means the old code path was never tested and the refactor is unverified. Tier survivors B unless the line is on the component's main path.

## Per-mutant loop

1. Mutate with the Edit tool: comment out the statement (`//`), or for a guard, remove just the condition's effect (e.g. comment out the early return). One mutant at a time.
2. Run the tests (stage-0 command map) for the mutated package **and for every other affected package of the branch** — a mutant in a shared package (`component-base`, `field-base`, `a11y-base`, …) often only breaks its consumers. Running the whole suite per mutant is deliberately skipped as too slow; note that narrowing in the report's skipped line.
3. **Expected: failure** (non-zero exit in at least one group).
4. Restore: `git checkout -- <file>`, then confirm `git diff --name-only` is empty before the next mutant.

## Surviving mutants

The line is not pinned by any test. Every survivor is a finding — tier the gap: **A** when the unpinned line is the branch's core new behavior (or, on a **fix**, any line of the fix itself), otherwise **B**.

- Record it as `confirmed` at its tier, with the `file:line` and the one-line description of the test that would pin it, so a follow-up can write exactly that test.
- A gap that cannot be pinned by a reasonable behavioral test — a defensive branch unreachable from the public API — is `accepted` with the reason.

Closing these gaps is `/agent-skills:mutation-coverage`'s job; it writes the tests this skill will not. Name it in the report next to the survivors, so report-only is a handoff rather than a dead end.

## End of stage

Assert all three, and say so in stage 5:

- `git diff --name-only` empty — no mutant left anywhere.
- `git diff --staged --name-only` empty — nothing was staged.
- `git rev-parse HEAD` == `<HEAD0>`.
