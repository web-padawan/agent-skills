---
name: self-review
description: Self-review the current branch (or its open PR) before opening or updating a PR. Detects the change type — bug fix, feature, refactor, chore — and runs three review passes in one parallel batch: a change pass (scope, behavior, fix correctness, plus boundary/impact blocks on the top significant changes), a code pass (logic, conventions, reuse, maintainability, comments) and a tests pass; the diff's scale tier (trivial/lite/full) sizes the coverage and deep-block budgets only. Never edits code — classifies findings A (must fix before merge) / B (follow-up) / C (taste) and writes a FINDINGS.md report with a ready / needs-work verdict. Use on your own branch; not for reviewing someone else's PR (guided-review, pr-review, adversarial-review).
argument-hint: "[parent-PR-or-issue-url] [--fix|--feature|--refactor|--chore] [--scale trivial|lite|full] [--deep N] [--no-coverage]"
disable-model-invocation: true
allowed-tools: Read, Write, Edit, Glob, Grep, Task, Agent, SendMessage, Skill, AskUserQuestion, Bash(git:*), Bash(gh:*), Bash(yarn:*), Bash(npm:*), Bash(npx:*), Bash(pnpm:*), Bash(*/scripts/get-pr-context.sh:*), Bash(*/scripts/review-plan.sh:*)
---

You review your own current branch before it becomes a PR or updates a PR. The optional
input `$0` is the parent PR or issue that is the source of this branch.

Three rules outrank everything else:

- **Never edit code.** Every step is read-only. The single carve-out is the coverage mutants
  in step 7, the only reason that `Edit` is in `allowed-tools`. Mutate one line at a time.
  Restore each line with `git checkout -- <path>` before the next mutant. The step ends only
  when `git status --porcelain --untracked-files=no` is empty again.
- **Never commit or stage.** Never run commit, amend, push, `git add`, `stash`,
  `reset --hard`, or `git clean`. `HEAD` and the index end exactly as you found them.
- **This skill creates only the context file, its notes file, the patch files for a diff too
  large to inline, and the report.** The plan script writes the skeleton and the patches in
  the git-ignored report directory that the plan names. You write the notes file before
  fan-out. You write the report only after the gate in step 6 approves it.

Every finding goes in the report as `confirmed` or `accepted`. Never drop a finding silently.

| Reference | Covers |
| --- | --- |
| [`../../references/pipeline.md`](../../references/pipeline.md) | Steps 1–5: the plan, the script-written context file and your notes file, the fan-out, the roll call, triage |
| [`../../references/severity.md`](../../references/severity.md) | A / B / C, the tie-breaker, type-aware tiering, deep-block severities |
| [`../../references/delivery.md`](../../references/delivery.md) | Launch rules, the delivery clause, roll call, escalation ladder |
| [`references/mutation.md`](references/mutation.md) | Step 7: mutant selection, restore safety, survivors as findings |
| [`references/finalize.md`](references/finalize.md) | Steps 6 and 8: the gate, the FINDINGS.md template, the verdict rubric |

Read each reference the first time that a step needs it. Do not read a reference twice in
a session. Relative paths resolve from this file. If a read fails, use
`${CLAUDE_PLUGIN_ROOT}/references/<name>.md` or
`${CLAUDE_PLUGIN_ROOT}/skills/self-review/references/<name>.md`.

## Steps

1. **Plan.** Resolve the plugin root to a literal path. Then run the plan script in one call:
   `${CLAUDE_PLUGIN_ROOT}/scripts/review-plan.sh --mode self` plus the flags that the user
   passed (`--fix|--feature|--refactor|--chore` → `--type`, `--scale`, `--deep N`,
   `--no-coverage`). If the output has a `guard: refuse:` line, say the reason in one line and
   stop. Record `base`, `head` and `head0` as literal SHAs. When the user gave `$0`, fetch it
   with `gh`.

   Per pipeline.md, resolve `type: undetermined` yourself. Re-run with `--type` so that the
   skeleton carries the type. Hand any `type_conflict` to the change pass.

   The script writes the context skeleton at the `context:` path from the plan. For a large
   diff, the script also writes the patch files that `diff_prod:` and `diff_tests:` name.
   **Never redirect a `git diff` yourself.** The diff must not pass through your context. When
   the plan prints `report_dir: SCRATCHPAD`, the script does not write the skeleton, because
   the default `.omc/` is not git-ignored here. In that case, re-run with
   `--report-dir <scratchpad>/self-review` so that the context, patches and report all land
   there.
2. **Write the notes file.** Write it with Write at the `notes:` path from the plan, per
   pipeline.md §2. It holds:
   - Settled facts that you verified beyond the skeleton, at a call or two each. Examples are
     the behavior of a helper, pre-change source, or a consumer elsewhere.
   - Open leads, with one owner pass each.
   - A one-line summary of `$0` when the user gave one.

   Never Edit the skeleton. The Read that Edit forces pulls the diff through your context.
   Skip the file when you have nothing to add.
3. **Fan out.** Send one message with one Agent call per pass. Use the `subagent_type`,
   `model` and prompt from the `=== PROMPTS ===` block of the plan, verbatim. Pass no `name`
   (delivery.md). The block already carries the lane of each pass, the deep budget and the
   effort ceiling. `--deep N` overrides the deep budget. A budget of `0` skips the blocks,
   never the pass.
4. **Assert nothing changed.** `git status --porcelain --untracked-files=no` must still be
   empty. If a pass edited anyway, revert those tracked files with `git checkout -- <path>`.
   Delete the files that the pass created, by path. Keep only the output of the pass as
   findings.

   The context, notes and patch files live in the git-ignored report directory, so they
   never appear here. Never run `git clean`. Never touch pre-existing untracked files.
5. **Roll call, then triage.** Do both per pipeline.md. Do the roll call first, by pass name.
6. **Gate.** Per finalize.md, print the classified list in chat. Then ask one
   `AskUserQuestion` with two questions: write the report, and run the coverage check. The
   skill applies nothing either way. The gate decides what you produce, not what you
   change.
7. **Coverage check.** Run it per mutation.md, with the `mutants` budget from the plan. Skip
   it when the gate skipped it or the budget is 0.
8. **Report and verdict.** Per finalize.md, assert that `HEAD` equals `head0` from the plan,
   with nothing unstaged and nothing staged. Write the report when the gate approved it. Reply
   in chat with the type, scale tier, tier counts, the reminder that nothing was changed,
   and the verdict. The verdict is **ready for PR** / **needs more work**.

The profile lives in [`../../references/profiles.md`](../../references/profiles.md) and
reaches you through the plan. The profile covers which passes run, the mutant budget and the
deep-block budget. Do not re-derive it here.
