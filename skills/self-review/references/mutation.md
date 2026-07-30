# Phase 6 — Coverage check

Purpose: verify the branch's tests pin its invariants. A mutant that survives — tests stay green while the change is broken — is a coverage gap. Skip this phase entirely when the gate chose "Skip the coverage check" or the profile has no budget (**chore**).

## Preconditions

- Everything you changed in phase 5 is staged and `git diff --name-only` is empty.
- `git status --porcelain --untracked-files=no` shows staged entries only.

> Restoring uses `git checkout -- <file>`, which resets the file to the **index**. That is safe *only* because the approved fixes are staged. If anything of yours is unstaged, stage it first — otherwise the restore destroys it.

## Mutant selection

Candidates: added/changed source lines in `git diff <BASE>..HEAD` (`<BASE>` = literal SHA from phase 0) — scope it to the repo's source globs, `-- 'packages/*/src/*.js'` in vaadin/web-components. Source only, never tests, never type declarations.

Skip lines that cannot produce a meaningful mutant: imports/exports, CSS/template-literal styling, JSDoc/comments, pure renames, lines whose removal is a syntax error that cannot be isolated.

Prioritize by logic density: conditionals and early returns > event listener add/remove > calculations and assignments > everything else. List skipped hunks in the report — silent truncation is forbidden.

### Budget and targeting per profile

- **fix — 5 mutants, and the whole-fix revert first.** Before any single-line mutant, revert the entire fix as one unit (`git stash` is forbidden — comment out the changed hunks, or `git checkout <BASE> -- <source file>` when the file's only change is the fix) and run the affected tests. **A new test must fail.** If every test still passes, the branch has no regression test for the bug it claims to fix — that is an A finding, the most important output of this phase. Restore, then spend the 5 mutants inside the fix's own hunks only; unrelated lines are not this branch's job.
- **feature — 15 mutants**, weighted to the feature's new behavior: the new public path first (the property setter, the event dispatch, the guard that makes the feature conditional), then its interaction with existing state (`disabled`, `readonly`, RTL), then everything else.
- **refactor — 10 mutants** on the refactored logic. A refactor with unchanged tests should kill everything; a survivor here usually means the old code path was never tested and the refactor is unverified. Tier survivors B unless the line is on the component's main path.

## Per-mutant loop

1. Mutate with the Edit tool: comment out the statement (`//`), or for a guard, remove just the condition's effect (e.g. comment out the early return). One mutant at a time.
2. Run the tests (phase-0 command map) for the mutated package **and for every other affected package of the branch** — a mutant in a shared package (`component-base`, `field-base`, `a11y-base`, …) often only breaks its consumers. Running the whole suite per mutant is deliberately skipped as too slow; note that narrowing in the report's skipped line.
3. **Expected: failure** (non-zero exit in at least one group).
4. Restore: `git checkout -- <file>`, then confirm `git diff --name-only` is empty before the next mutant.

## Surviving mutants

The line is not pinned by any test. Tier the gap: **A** when the unpinned line is the branch's core new behavior (or, on a **fix**, any line of the fix itself), otherwise **B**.

- Gate authorized tests → write one that fails against the mutant and passes against the real code; name and place it like the neighboring tests and assert observable behavior (no private APIs). Re-apply the mutant to confirm it fails, restore, confirm it passes, then `git add <test path>`. Record as `fixed`.
- Gate said report only → record as `deferred` at its tier, with the file:line so a follow-up can pin it.
- Cannot be pinned by a reasonable behavioral test (a defensive branch unreachable from the public API) → `accepted` with the reason.

End of phase: `git diff --name-only` empty, no mutant left anywhere, only staged changes present.
