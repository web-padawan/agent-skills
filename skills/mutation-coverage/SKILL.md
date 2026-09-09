---
name: mutation-coverage
description: Find source lines and expressions no test asserts on via mutation testing (line-removal by default, Stryker on request), then close each gap with a test that fails when the code is broken. Scopes to a file, a package, or the branch diff, and estimates runtime before mutating.
argument-hint: "<file|--package <pkg>|--diff> [--stryker] [--test '<command>']"
disable-model-invocation: true
---

Run mutation testing on the requested scope. Then add a test for every real
survivor. Each test must fail on broken code, so that the suite fails too. Produce a
Markdown report of the process.

Scripts and assets live next to this file. If a relative path fails, use
`${CLAUDE_PLUGIN_ROOT}/skills/mutation-coverage/<path>`.

| Resource | Covers |
| --- | --- |
| `scripts/mutate.mjs` | Line-removal engine (`--help` for all options) |
| `scripts/stryker-diff.mjs` | Diff mode: changed lines → per-package Stryker runs |
| `assets/stryker/` | Config templates materialized into the target repo |
| [`references/stryker.md`](references/stryker.md) | Stryker engine: materialize, run, estimate, cleanup |
| [`references/survivors.md`](references/survivors.md) | Survivor classification, read it before you write any test |

## Engine and scope

Two engines exist. The scope usually selects the engine.

- **Line-removal** (`scripts/mutate.mjs`) is the default for a single file. It
  deletes one line at a time and reruns the suite. A survivor is a line that no
  test asserts on. It needs zero setup and works in any repo with a test command
  that exits non-zero on failure. It creates one mutant per line, so the cost is
  predictable.
- Use **Stryker** for `--diff` and `--package` scopes, or when the user requests
  it (`--stryker`). Its real mutation operators (`>`→`>=`, `&&`→`||`, literal
  swaps) catch wrong-operator gaps that line-removal cannot express. The
  incremental cache makes reruns near-free.

  Read `references/stryker.md` the first time that the session needs it. If the
  repo has `stryker.conf.js` committed, use the setup of the repo. Otherwise
  materialize the templates of this skill as untracked files. Never commit config
  or add dependencies.

| Scope | Invocation | Engine |
| --- | --- | --- |
| one file (default) | `<file>` | line-removal, `--stryker` to switch |
| branch diff (pre-PR) | `--diff` | Stryker, changed line ranges only, one run per package |
| whole package | `--package <pkg>` | Stryker, background job |

Input also accepts `--test '<command>'`. If the user gives no test command, derive
the narrowest command that covers the scope. For example, in vaadin/web-components
use `yarn test --group <pkg>`, plus `--glob` when a dedicated test file exists. If
you cannot determine the scope or a suitable test command, stop and ask.

## Workflow

1. **Baseline + estimate + full run.** Time one test-suite run first. The cost is
   about baseline time × mutant count. Line-removal has one mutant per candidate
   line. Stryker prints `Instrumented … with M mutant(s)` within seconds.

   State the estimate. If the estimate exceeds about 30 minutes, do not start
   silently. Narrow the scope, or get an explicit OK for a long background run.
   Then start the mutation run in the background:
   - line-removal: `node scripts/mutate.mjs <file> --test '<command>'`. Results
     land in `.mutate/<basename>.jsonl` (`killed` / `SURVIVED` / `syntax` per line).
   - Stryker: follow `references/stryker.md`. Survivors appear in the clear-text
     output and in `reports/mutation/<group>-incremental.json`.

   Both engines restore the source on exit. Still, verify afterwards with
   `git status` that the source has no changes. While the run executes, read the
   target source and the existing tests for the package.

2. **Classify every survivor** per `references/survivors.md` before you write
   anything. The classes are coverage gap, masked write, self-referential
   assertion, untestable helper, structurally unkillable, or (Stryker) equivalent
   mutant. Only the first four get tests. The rest get a one-line justification
   in the report.

3. **Iterate survivor by survivor: break → failing test → restore.** Add exactly
   one test case per survivor. The test must fail with the mutation applied and
   pass on pristine source. Add NO other tests.

   To develop a tricky test, apply the mutation temporarily. Delete the line with
   `sed -i '<n>d'`, or make the edit of the Stryker operator with the Edit tool.
   Confirm that the new test fails. Then restore the pristine source.

   Match the style and structure of the existing test files. Integrate new tests
   into existing describes where they fit. Use fake timers for anything over
   100 ms. Follow `CONVENTIONS.md` in the repo.

4. **Verify.** First, the whole suite must pass on pristine source. Then re-run
   only the survivors:
   - line-removal: `node scripts/mutate.mjs <file> --test '<command>' --retest-survivors`.
     The script runs the remove, run, restore cycle per line. It records which
     test killed each line. Line numbers refer to the pristine file. The script
     re-locates lines by content, so they stay valid after test-only edits.
   - Stryker: rerun the same command. The incremental cache retests only mutants
     whose verdict can change.

   Iterate on each survivor that remains and that you did not classify as
   unkillable.

5. **Report.** Write `mutation-report-<scope>.md` in the repository root:
   - Summary table: killed / survived / ignored / syntax counts before and after.
   - **Survivor → added test case name** table for every killed survivor. Take
     the names from `failedTests` in the retest `.mutate/*.jsonl` log, or from
     the Stryker `killedBy` data.
   - Table of remaining unkillable/equivalent mutants with the justification
     for each.
   - Any bugs, dead code, or duplicated logic that you discovered on the way.

   Run lint/format checks on the changed test files before you finish.

Done condition, all of these hold:

- The full suite passes on pristine source.
- You killed every survivor, or you documented it as unkillable in the report.
- `git status` shows only changed test files and the report. For Stryker, the
  untracked materialized files listed in `.git/info/exclude` may also appear.
- After a Stryker run, `git status --porcelain -- <source root>` is empty (see
  cleanup in `references/stryker.md`).
