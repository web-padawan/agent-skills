# Phase 4 — Mutation check

Purpose: verify the branch's tests pin its invariants. A mutant that survives (tests stay green with the change broken) is a coverage gap.

Precondition: `git status --porcelain` clean. A phase-3 commit exists when fixes were applied; when phase 3 changed nothing, the tree is clean anyway — proceed.

## Mutant selection

Candidates: added/changed source lines in `git diff <BASE>..HEAD` (`<BASE>` = literal SHA from phase 0) — scope it to the repo's source globs, `-- 'packages/*/src/*.js'` in vaadin/web-components. Source only, never tests, never type declarations.

Skip lines that cannot produce a meaningful mutant: imports/exports, CSS/template-literal styling, JSDoc/comments, pure renames, lines whose removal is a syntax error that cannot be isolated.

Prioritize by logic density: conditionals and early returns > event listener add/remove > calculations and assignments > everything else. **Budget: 15 mutants per run.** List skipped hunks in the report — silent truncation is forbidden.

## Per-mutant loop

1. Mutate with the Edit tool: comment out the statement (`//`), or for a guard, remove just the condition's effect (e.g. comment out the early return). One mutant at a time.
2. Run the tests (phase-0 command map) for the mutated package **and for every other affected package of the branch** — a mutant in a shared package (`component-base`, `field-base`, `a11y-base`, …) often only breaks its consumers. Running the whole suite for every mutant is deliberately skipped as too slow; note that narrowing in the report's skipped line.
3. **Expected: failure** (non-zero exit in at least one group).
4. Restore with `git checkout -- <file>` and confirm `git status --porcelain` is clean before the next mutant.

## Surviving mutants

Tests passed with the line broken → gap. For each survivor:
1. Write a test that fails against the mutant and passes against the real code — name and place it like the neighboring tests, assert observable behavior (no private APIs).
2. Re-apply the mutant, confirm the new test fails, restore, confirm it passes.
3. Record as a `tests` finding marked `fixed` (the new test is the fix); the new test gets amended into the commit in phase 5.

A survivor you cannot pin with a reasonable behavioral test (e.g. defensive branch unreachable from public API) → `accepted` + reason.
