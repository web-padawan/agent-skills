---
name: self-review
description: Self-review the current branch (or its open PR) before opening or updating a PR. Detects the change type — bug fix, feature, refactor, chore — and runs three review passes in one parallel batch: a change pass (scope, behavior, fix correctness, plus boundary/impact blocks on the top significant changes), a code pass (logic, conventions, reuse, maintainability, comments) and a tests pass; the diff's scale tier (trivial/lite/full) sizes the coverage and deep-block budgets only. Never edits code — classifies findings A (must fix before merge) / B (follow-up) / C (taste) and writes a FINDINGS.md report with a ready / needs-work verdict. Use on your own branch; not for reviewing someone else's PR (guided-review, pr-review, adversarial-review).
argument-hint: "[parent-PR-or-issue-url] [--fix|--feature|--refactor|--chore] [--scale trivial|lite|full] [--deep N] [--no-coverage]"
disable-model-invocation: true
allowed-tools: Read, Write, Edit, Glob, Grep, Task, Agent, SendMessage, Skill, AskUserQuestion, Bash(git:*), Bash(gh:*), Bash(yarn:*), Bash(npm:*), Bash(npx:*), Bash(pnpm:*), Bash(*/scripts/get-pr-context.sh:*), Bash(*/scripts/review-plan.sh:*)
---

You are self-reviewing the current branch before it becomes (or updates) a PR. Optional
input `$0` is the parent PR or issue this branch was extracted from.

Three rules outrank everything else:

- **Never edit code.** Every step is read-only. The single carve-out is step 7's coverage
  mutants: one line at a time, restored with `git checkout -- <path>` before the next, and
  the step ends only when `git status --porcelain --untracked-files=no` is empty again.
  (`Edit` is in `allowed-tools` for that carve-out alone.)
- **Never commit or stage.** No commit, amend, push, `git add`, `stash`, `reset --hard`, or
  `git clean` — ever. `HEAD` and the index end exactly as found.
- **The only files this skill creates are the two prepared patches, the context file and
  the report**, all in the git-ignored report directory the plan names, and the report only
  after step 6's gate approves it.

Every finding ends up in the report as `confirmed` or `accepted`. Nothing is silently dropped.

| Reference | Covers |
| --- | --- |
| [`../../references/pipeline.md`](../../references/pipeline.md) | Steps 1–5: the plan, the patches and context file, the read discipline, the fan-out, the roll call, triage |
| [`../../references/severity.md`](../../references/severity.md) | A / B / C, the tie-breaker, type-aware tiering, deep-block severities |
| [`../../references/delivery.md`](../../references/delivery.md) | Launch rules, the delivery clause, roll call, escalation ladder |
| [`references/mutation.md`](references/mutation.md) | Step 7: mutant selection, restore safety, survivors as findings |
| [`references/finalize.md`](references/finalize.md) | Steps 6 and 8: the gate, the FINDINGS.md template, the verdict rubric |

Read each one the **first time** a step needs it, never twice in a session. Relative paths
resolve from this file; if a read fails, use `${CLAUDE_PLUGIN_ROOT}/references/<name>.md` or
`${CLAUDE_PLUGIN_ROOT}/skills/self-review/references/<name>.md`.

## Steps

1. **Plan.** Run the plan script — one call, the plugin root resolved to a literal path:
   `${CLAUDE_PLUGIN_ROOT}/scripts/review-plan.sh --mode self` plus the flags the user passed
   (`--fix|--feature|--refactor|--chore` → `--type`, `--scale`, `--deep N`, `--no-coverage`).
   A `guard: refuse:` line ends the run — say the reason in one line and stop. Record `base`,
   `head` and `head0` as literal SHAs. Fetch `$0` with `gh` when given. Per pipeline.md,
   resolve `type: undetermined` yourself and hand any `type_conflict` to the change pass.
2. **Patches, then context file.** Write the prod and test patches at the plan's
   `patch_prod:` / `patch_tests:` paths — **with a shell redirect**, so the diff lands in a
   file without passing through your own context either. Then the context file at its
   `context:` path. Both per pipeline.md §2, including the conventions excerpt and the
   read-discipline block verbatim: everything a pass would otherwise re-derive is settled
   here, once.
3. **Fan out.** Launch the plan's `passes` in one message, per pipeline.md and delivery.md.
   Give each pass **only the patch its `reads`
   lane names**: that column, not the pass count, is what the profile's token cost turns on.
   The plan's `deep` number reaches the change pass as its block budget (`--deep N`
   overrides it; `0` skips the blocks, never the pass).
4. **Assert nothing changed.** `git status --porcelain --untracked-files=no` still empty. If a
   pass edited anyway: revert those tracked files with `git checkout -- <path>`, delete files
   it created **by path**, keep only its output as findings. The patches live in the
   git-ignored report directory, so they never show up here. Never `git clean`; never touch
   pre-existing untracked files.
5. **Roll call, then triage.** Both per pipeline.md — the roll call first, by pass name.
6. **Gate.** Per finalize.md: the classified list in chat, then one `AskUserQuestion` — write
   the report, and run the coverage check. Nothing is applied either way; the gate decides
   what gets **produced**, not what gets **changed**.
7. **Coverage check.** Per mutation.md, with the plan's `mutants` budget, unless the gate
   skipped it or the budget is 0.
8. **Report and verdict.** Per finalize.md: assert `HEAD` == the plan's `head0`, nothing
   unstaged, nothing staged; write the report when the gate approved it; reply in chat with
   the type, the scale tier, tier counts, the reminder that **nothing was changed**, and the
   verdict: **ready for PR** / **needs more work**.

The profile itself — which passes run, the mutant budget and the deep-block budget — lives in
[`../../references/profiles.md`](../../references/profiles.md) and reaches you through the
plan. Do not re-derive it here. Why the pipeline is shaped this way:
[`../../references/rationale.md`](../../references/rationale.md).
