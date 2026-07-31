---
name: mutation-coverage
description: Find source lines and expressions no test asserts on via mutation testing (line-removal by default, Stryker on request), then close each gap with a test that fails when the code is broken. Scopes to a file, a package, or the branch diff, and estimates runtime before mutating.
argument-hint: "<file|--package <pkg>|--diff> [--stryker] [--test '<command>']"
disable-model-invocation: true
---

Run mutation testing on the requested scope, then add a test for every real
survivor so that breaking the code makes the suite fail. Produce a Markdown
report of the process.

Scripts and assets live next to this file; if a relative path fails, use
`${CLAUDE_PLUGIN_ROOT}/skills/mutation-coverage/<path>`.

| Resource | Covers |
| --- | --- |
| `scripts/mutate.mjs` | Line-removal engine (`--help` for all options) |
| `scripts/stryker-diff.mjs` | Diff mode: changed lines → per-package Stryker runs |
| `assets/stryker/` | Config templates materialized into the target repo |
| [`references/stryker.md`](references/stryker.md) | Stryker engine: materialize, run, estimate, cleanup |
| [`references/survivors.md`](references/survivors.md) | Survivor classification — read before writing any test |

## Engine and scope

Two engines; the scope usually picks the engine.

- **Line-removal** (`scripts/mutate.mjs`) — default for a single file. Deletes
  one line at a time and reruns the suite; a surviving line is a line no test
  asserts on. Zero setup, works in any repo with a test command that exits
  non-zero on failure. One mutant per line → predictable cost.
- **Stryker** — used for `--diff` and `--package` scopes, or when the user asks
  for it (`--stryker`). Real mutation operators (`>`→`>=`, `&&`→`||`, literal
  swaps) catch wrong-operator gaps line-removal cannot express, and the
  incremental cache makes reruns near-free. Read `references/stryker.md` the
  first time the session needs it: if the repo has `stryker.conf.js` committed,
  use the repo's setup; otherwise materialize the skill's templates as
  untracked files — never commit config or add dependencies.

| Scope | Invocation | Engine |
| --- | --- | --- |
| one file (default) | `<file>` | line-removal; `--stryker` to switch |
| branch diff (pre-PR) | `--diff` | Stryker, changed line ranges only, one run per package |
| whole package | `--package <pkg>` | Stryker, background job |

Input also accepts `--test '<command>'`. If not given, derive the narrowest
command that covers the scope (e.g. `yarn test --group <pkg>` in
vaadin/web-components, plus `--glob` when a dedicated test file exists). If
neither the scope nor a suitable test command can be determined, stop and ask.

## Workflow

1. **Baseline + estimate + full run.** Time one test-suite run first. Cost ≈
   baseline time × mutant count (line-removal: one mutant per candidate line;
   Stryker prints `Instrumented … with M mutant(s)` within seconds). State the
   estimate; if it exceeds ~30 minutes, do not start silently — narrow the
   scope or get an explicit OK for a long background run. Then start the
   mutation run in the background:
   - line-removal: `node scripts/mutate.mjs <file> --test '<command>'` — results
     land in `.mutate/<basename>.jsonl` (`killed` / `SURVIVED` / `syntax` per line)
   - Stryker: per `references/stryker.md` — survivors in the clear-text output
     and `reports/mutation/<group>-incremental.json`

   Both engines restore the source on exit; still verify with `git status`
   afterwards that the source is untouched. While the run executes, read the
   target source and the existing tests for the package.

2. **Classify every survivor** per `references/survivors.md` before writing
   anything: coverage gap, masked write, self-referential assertion, untestable
   helper, structurally unkillable, or (Stryker) equivalent mutant. Only the
   first four get tests; the rest get a one-line justification in the report.

3. **Iterate survivor by survivor: break → failing test → restore.** Add
   exactly one test case per survivor that fails while the mutation is applied
   and passes on pristine source. Add NO other tests. While developing a tricky
   test, temporarily apply the mutation (delete the line via `sed -i '<n>d'`,
   or make the Stryker operator's edit with the Edit tool), confirm the new
   test fails, then restore the pristine source. Match the existing test files'
   style and structure — integrate into existing describes where they fit; use
   fake timers for anything over 100 ms; follow the repo's `CONVENTIONS.md`.

4. **Verify.** First the whole suite must be green on pristine source. Then
   re-run only the survivors:
   - line-removal: `node scripts/mutate.mjs <file> --test '<command>'
     --retest-survivors` — performs the remove → run → restore cycle per line
     and records which test killed it (line numbers refer to the pristine file;
     lines are re-located by content, so they stay valid after test-only edits)
   - Stryker: rerun the same command — the incremental cache retests only
     mutants whose verdict can change

   Iterate on anything still surviving that is not classified unkillable.

5. **Report.** Write `mutation-report-<scope>.md` in the repository root:
   - Summary table: killed / survived / ignored / syntax counts before and after.
   - **Survivor → added test case name** table for every killed survivor (from
     `failedTests` in the retest `.mutate/*.jsonl` log, or the Stryker
     `killedBy` data).
   - Table of remaining unkillable/equivalent mutants with the justification
     for each.
   - Any bugs, dead code, or duplicated logic discovered along the way.

   Run lint/format checks on the changed test files before finishing.

Done condition: the full suite passes on pristine source, every survivor is
either killed or documented as unkillable in the report, `git status` shows
only test files and the report changed (plus, for Stryker, the untracked
materialized files listed in `.git/info/exclude`), and — after a Stryker run —
`git status --porcelain -- <source root>` is empty (see cleanup in
`references/stryker.md`).
