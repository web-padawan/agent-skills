# How to split and order refactor work

## Split a pure move from a behavior change

A pull request that mixes a move and a timing change is hard to review. A reviewer cannot tell
which hunk is safe. Split the work.

The first pull request holds the pure move. No observer list changes. No lifecycle hook
changes. A reviewer verifies each hunk by a comparison of the old body against the new body.

The second pull request holds the behavior change. It depends on the first one. Its body states
the root cause and names the test that found it.

## Prove that the move is pure

Compare the observer list and the property declarations of each changed file against the base
branch.

```bash
git diff <base>...HEAD -- <paths> | grep -E '^[+-].*(observer|static get properties)'
```

The output must be empty. Add the comparison result to the pull request body when the move is
large.

A pure move also leaves the public API unchanged. Read the diff of the type definition files and
confirm that they gained and lost the same declarations.

```bash
git diff <base>...HEAD -- '**/*.d.ts'
```

## Order a program of several refactors

A feature branch is often in review on the same files. Every merged refactor costs that branch
a rebase. Order the work with these rules.

1. Land a refactor that shrinks the diff of the in-flight feature before that feature.
2. Do not land a refactor that helps only after a rewrite of the feature. A rewrite of a branch
   that is already in review costs more than it returns.
3. A helper with no caller until the feature arrives must ship with the feature. A helper that
   waits alone in the base branch is dead code.
4. Land a refactor that edits the same snapshot files as the feature after the feature, and
   alone.
5. Put the largest extraction last. It gains nothing from an earlier position and it forces the
   widest rebase.

## Check the interaction before you promise an order

For each candidate refactor, answer three questions.

Does the feature call a method whose signature this refactor changes? An extra argument that
the new signature ignores is not a break. It leaves dead arguments and no rebase pressure.

Does the refactor and the feature both insert into the same lifecycle hook? That is a conflict
in every rebase.

Does the refactor edit a file that the feature also edits? Snapshot files are the common case.
