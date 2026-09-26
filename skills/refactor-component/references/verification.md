# Proof that a refactor kept the behavior

A passing suite proves that the old paths still work. It does not prove that a test covers the
code that you moved. Use both checks below.

## Which suites to run

1. Search all packages for the name of each mixin that you changed.
2. Run the unit suite of every package in the result, not only the package that you edited.
3. Run the DOM snapshot suite of each of those packages.
4. Run the type check of the repository.

A change to a base mixin often reaches several packages. A change that reaches only one
package is a sign that the code was not shared and that the move has no value.

Run the suites with `${CLAUDE_PLUGIN_ROOT}/scripts/test-summary.sh --group <pkg> --group <pkg>
--suites unit,snapshots`. It prints one line per suite and the names of the failing tests.

## The green baseline rule

Run the full target suite before any measurement. Confirm zero failures.

A measurement against a red baseline reports noise. The risk is highest after an edit to a test
file, because a broken test can absorb the signal of an unrelated mutation. Never skip this
step, even when the previous run was green.

## A/B probe

A green suite proves only what the tests assert. A component with a `sync: true` property
re-enters its update on assignment, and a setter returns early on an equal value. A difference
can hide in a path that no test reads. Prove that the behavior is unchanged with a probe.

1. Write a throwaway test `packages/<pkg>/test/zz-probe.test.js`. Print the observable state
   with `console.log` across a sweep of inputs. Examples are `value`, the input value, and
   event counts.
2. Run `${CLAUDE_PLUGIN_ROOT}/scripts/ab.sh --ref <base> --path <src> -- yarn test --group <pkg> --glob zz-probe`.
   Name every changed source file with a `--path`.
   The script runs the probe on both trees, restores the files, and diffs the two outputs.
3. Report the sweep size and the diff result. A green suite alone is not a result.
4. Delete the probe before you commit. The `no-console` rule fails lint.

For a layout or a paint behavior, use `${CLAUDE_PLUGIN_ROOT}/scripts/probe.cjs` against a dev
page instead. Record one result file per tree with `--out`. Compare the two files with
`probe-compare.cjs`. The harness starts the dev server. Pass `--port 8765` to `ab.sh` when
the command reads from that server, because a running server can keep an old module.

## Mutation checks

These checks break one decision at a time. The `mutation-coverage` skill removes lines instead,
so it answers a different question. Use both when you need a full coverage picture.

A pure move keeps the behavior. A revert of a moved piece therefore also passes, and proves
nothing. Break the piece instead, then confirm that a test fails.

Commit the refactor before you mutate. Confirm that `git status` reports a clean tree.

For each piece that you moved:

1. Break that piece by hand. Make the new code return a wrong value, match a wrong key, or skip
   a call.
2. Run the suites of the affected packages. Record the count of failures.
3. Restore the file with `git checkout HEAD -- <path>`. Confirm that the working tree is clean.
4. Repeat for the next piece.

Record one line per piece: the piece, the mutation, and the count of failures. The table
belongs in the pull request body.

## How the isolation fails silently

A stash of a path that holds no uncommitted change creates no stash entry. The run then measures
the committed code and reports a false pass. Do not use `git stash` for the isolation. The
`ab.sh` script swaps with `git checkout <ref> -- <path>` and restores on every exit. It
refuses when a path holds uncommitted work.

A `git checkout HEAD -- <path>` discards uncommitted work in that path. Commit first.

Both failures look like a passing run. Check `git status` after each restore.

## How to read an uncaught mutation

A mutation that no test catches has two possible causes.

A coverage gap. A public path reaches the code and no test asserts on the result. Add a test.
Use the `mutation-coverage` skill to find the full gap and to close it.

An unreachable change. No public path can produce a difference. A change that only aligns one
call site with the rest of a file is often in this class. Keep the change and state in the pull
request that no test can catch it. Do not build a test that constructs an unreachable state.

## Consumers outside the repository

Server side integrations and test helper libraries read members with an underscore prefix.
Before you move or rename such a member, search the consumer repository for each member name.

When the search finds a match, run the integration test module of the consumer for the touched
component against the local checkout. The consumer repository holds a setting that points its
build at a local web components checkout. Restore that setting after the run, because a build
that keeps it produces confusing results later.
