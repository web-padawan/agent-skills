# Coverage check (step 7)

Purpose: verify that the tests of the branch pin its invariants. A mutant survives when the
tests stay green while the change is broken. A survivor is a coverage gap, and here it
becomes a finding. This skill never writes the missing test. Skip the step entirely when
the gate chose `Skip it` or the `mutants:` budget from the plan is 0.

This is the one step that writes to a tracked file, and the only carve-out of the skill from
the no-edit rule. Every mutant is temporary. Restore each mutant before the next. Never stage
a mutant.

## Preconditions

- `git status --porcelain --untracked-files=no` is empty.
- `git rev-parse HEAD` still equals `head0` from the plan.

> The restore uses `git checkout -- <file>`, which resets the file to the **index**. Because
> this skill never stages anything, the index equals `HEAD`, so the restore is exact and
> total. That is the whole safety argument, and it holds only while the tree is clean.

If the tree is dirty at the start of the step or at any mutant boundary, stop the step and
report the dirty tree as a finding. Never use `git clean` or `git stash`.

## Mutant selection

Candidates are the added or changed source lines in `git diff <base>..<head>` (literal SHAs
from the plan), scoped to the `src_glob` of the plan. Use source only, never tests and never
type declarations.

Skip lines that cannot produce a meaningful mutant:

- imports/exports
- CSS/template-literal styling
- JSDoc/comments
- pure renames
- lines whose removal is a syntax error that you cannot isolate

Prioritize by logic density: conditionals and early returns > event listener add/remove >
calculations and assignments > everything else. Weight toward lines that the earlier passes
already flagged. A mutant on a flagged line is worth more than one on an incidental line. List
every skipped hunk in the report.

**`mutant_pool: 0` means stop.** The plan counts what the styling skip leaves. When the count
is zero, the report gets one line: `no mutants: the prod diff is styling only`.

**Screenshot-only coverage weakens the signal.** A mutant under a visual test dies only if it
moves enough pixels to clear the tolerance of the runner (find it in the visual-test config).
So a mutation that genuinely breaks a small color or spacing change can survive. Report such
a survivor as *unpinned within tolerance*, not as a plain coverage gap.

### Targeting per type

The plan prints the effective budget (`mutants:`), already capped by the scale tier. The type
changes only where the budget goes:

- **fix: the whole-fix revert first, at every scale.** Before any single-line mutant, revert
  the entire fix as one unit. Then run the affected tests. Disable the changed hunks with
  comments, or use `git checkout <base> -- <source file>` when the only change in the file is
  the fix. A new test must fail.

  If every test still passes, the branch has no regression test for the bug that it claims to
  fix. That is an A finding, and the most important output of this step. Restore the fix.
  Then spend the budget inside the hunks of the fix only.
- **feature**: weight the budget to the new behavior. Mutate the new public path first (the
  property setter, the event dispatch, the guard that makes the feature conditional). Then
  mutate its interaction with existing state (`disabled`, `readonly`, RTL). Then mutate
  everything else.
- **refactor**: spend the budget on the refactored logic. A refactor with unchanged tests
  should kill everything. A survivor usually means that the old path was never tested and the
  refactor is unverified. Tier survivors B unless the line is on the main path of the
  component.

## Per-mutant loop

1. Mutate with the Edit tool. Disable the statement with a comment (`//`), or for a guard,
   remove only the effect of the condition (for example, disable the early return). Apply one
   mutant at a time.
2. Run the tests (the `commands:` from the plan) for the mutated package **and every other
   package in `affected_packages` from the plan**. A mutant in a shared package
   (`component-base`, `field-base`, `a11y-base`, and so on) often only breaks its consumers.
   That narrow run is what keeps the step affordable. Note it in the report.
3. **Expected: failure** (non-zero exit in at least one group).
4. Restore with `git checkout -- <file>`. Then confirm that `git diff --name-only` is empty
   before the next mutant.

## Surviving mutants

A survivor means that no test pins the line. Every survivor is a finding. Tier the gap A
when the unpinned line is the core new behavior of the branch. On a `fix`, also tier any
line of the fix itself A. Otherwise tier the gap B.

- Record the survivor as `confirmed` at its tier. Give the `file:line` and a one-line
  description of the test that would pin it. Then a follow-up can write exactly that test.
- A gap that no reasonable behavioral test could pin, for example a defensive branch
  unreachable from the public API, is `accepted` with the reason.

`/agent-skills:mutation-coverage` closes these gaps. Name it in the report next to the
survivors. Then a report-only run is a handoff rather than a dead end.

## End of step

Assert all three. Then say so in step 8:

- `git diff --name-only` empty: no mutant remains anywhere.
- `git diff --staged --name-only` empty: nothing is staged.
- `git rev-parse HEAD` == `head0` from the plan.
