# Coverage check (step 7)

Purpose: verify the branch's tests pin its invariants. A mutant that survives — tests stay
green while the change is broken — is a coverage gap, and here it becomes a **finding**. This
skill never writes the missing test. Skip the step entirely when the gate chose `Skip it` or
the plan's `mutants:` budget is 0.

This is the one step that writes to a tracked file, and the skill's only carve-out from the
no-edit rule. Every mutant is temporary, restored before the next, and never staged.

## Preconditions

- `git status --porcelain --untracked-files=no` is empty.
- `git rev-parse HEAD` still equals the plan's `head0`.

> Restoring uses `git checkout -- <file>`, which resets the file to the **index**. Because
> this skill never stages anything, the index equals `HEAD`, so the restore is exact and
> total. That is the whole safety argument, and it holds only while the tree is clean.

If the tree is dirty at the start of the step or at any mutant boundary, **stop the step** and
report it as a finding. Do not reconcile, do not guess which change was yours, and never reach
for `git clean` or `git stash`.

## Mutant selection

Candidates: added/changed source lines in `git diff <base>..<head>` (literal SHAs from the
plan), scoped to the plan's `src_glob`. Source only — never tests, never type declarations.

Skip lines that cannot produce a meaningful mutant: imports/exports, CSS/template-literal
styling, JSDoc/comments, pure renames, lines whose removal is a syntax error that cannot be
isolated.

Prioritize by logic density: conditionals and early returns > event listener add/remove >
calculations and assignments > everything else. Weight toward lines the earlier passes already
flagged — a mutant on a flagged line is worth more than one on an incidental line. List
skipped hunks in the report; silent truncation is forbidden.

**`mutant_pool: 0` means stop.** The plan counts what the styling skip leaves; when it is
zero, the report gets one line — `no mutants: the prod diff is styling only` — never mutants
on CSS declarations.

**Screenshot-only coverage weakens the signal.** A mutant under a visual test dies only if it
moves enough pixels to clear the runner's tolerance (find it in the visual-test config), so a
small colour or spacing change survives a mutation it genuinely broke. Report such a survivor
as *unpinned within tolerance*, not as a plain coverage gap.

### Targeting per type

The plan prints the effective budget (`mutants:`), already capped by the scale tier. What
changes per type is **where** the budget goes:

- **fix — the whole-fix revert first, at every scale.** Before any single-line mutant, revert
  the entire fix as one unit (`git stash` is forbidden — comment out the changed hunks, or
  `git checkout <base> -- <source file>` when the file's only change is the fix) and run the
  affected tests. **A new test must fail.** If every test still passes, the branch has no
  regression test for the bug it claims to fix — an A finding, and the most important output
  of this step. Restore, then spend the budget inside the fix's own hunks only.
- **feature** — weighted to the new behavior: the new public path first (the property setter,
  the event dispatch, the guard that makes the feature conditional), then its interaction with
  existing state (`disabled`, `readonly`, RTL), then everything else.
- **refactor** — on the refactored logic. A refactor with unchanged tests should kill
  everything; a survivor usually means the old path was never tested and the refactor is
  unverified. Tier survivors B unless the line is on the component's main path.

## Per-mutant loop

1. Mutate with the Edit tool: comment out the statement (`//`), or for a guard, remove just
   the condition's effect (e.g. comment out the early return). One mutant at a time.
2. Run the tests (the plan's `commands:`) for the mutated package **and every other package in
   the plan's `affected_packages`** — a mutant in a shared package (`component-base`,
   `field-base`, `a11y-base`, …) often only breaks its consumers. Running the whole suite per
   mutant is deliberately skipped as too slow; note that narrowing in the report.
3. **Expected: failure** (non-zero exit in at least one group).
4. Restore: `git checkout -- <file>`, then confirm `git diff --name-only` is empty before the
   next mutant.

## Surviving mutants

The line is not pinned by any test. Every survivor is a finding — tier the gap: **A** when the
unpinned line is the branch's core new behavior (or, on a **fix**, any line of the fix itself),
otherwise **B**.

- Record it as `confirmed` at its tier with the `file:line` and a one-line description of the
  test that would pin it, so a follow-up can write exactly that test.
- A gap no reasonable behavioral test could pin — a defensive branch unreachable from the
  public API — is `accepted` with the reason.

Closing these gaps is `/agent-skills:mutation-coverage`'s job; it writes the tests this skill
will not. Name it in the report next to the survivors, so report-only is a handoff rather than
a dead end.

## End of step

Assert all three, and say so in step 8:

- `git diff --name-only` empty — no mutant left anywhere.
- `git diff --staged --name-only` empty — nothing was staged.
- `git rev-parse HEAD` == the plan's `head0`.
