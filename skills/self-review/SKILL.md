---
name: self-review
description: Self-review the current branch (or its open PR) before opening or updating a PR. Detects the change type — bug fix, feature, refactor, chore — and runs three review passes in one parallel batch: a change pass (scope, behavior, fix correctness, plus boundary/impact blocks on the top significant changes), a code pass (logic, conventions, reuse, maintainability, comments) and a tests pass; the diff's scale tier (trivial/lite/full) sizes the coverage, deep-block and rounds budgets only. A large feature gets a second round that looks for what the first missed, and a run on a newer head reconciles the findings of the last run. Never edits code — classifies findings A (must fix before merge) / B (follow-up) / C (taste) and writes a FINDINGS.md report with a ready / needs-work verdict. Use on your own branch; not for reviewing someone else's PR (pr-review).
argument-hint: "[parent-PR-or-issue-url] [--fix|--feature|--refactor|--chore] [--rounds N] [--fresh] [--no-coverage]"
disable-model-invocation: true
allowed-tools: Read, Write, Edit, Glob, Grep, Task, Agent, SendMessage, AskUserQuestion, Bash(git:*), Bash(gh:*), Bash(yarn:*), Bash(npm:*), Bash(npx:*), Bash(pnpm:*), Bash(mvn:*), Bash(*/scripts/get-pr-context.sh:*), Bash(*/scripts/review-plan.sh:*), Bash(*/scripts/ab.sh:*)
---

You review your own current branch before it becomes a PR or updates a PR. The optional
input `$0` is the parent PR or issue that is the source of this branch.

Three rules outrank everything else:

- **Every step is read-only.** The only carve-out is the `coverage` stage of the
  `after-gate` slot. It is the only reason that `Edit` is in `allowed-tools`. Mutate one
  line at a time. Restore each line with `git checkout -- <path>` before the next mutant.
  The stage ends only when `git status --porcelain --untracked-files=no` is empty again.
- **Leave `HEAD` and the index exactly as you found them.** Never run commit, amend, push,
  `git add`, `stash`, `reset --hard`, or `git clean`.
- **This skill creates only the context file, its notes file, the patch files for a diff too
  large to inline, the findings file and the report.** The plan script writes the skeleton
  and the patches in the report directory that the plan names, inside the git directory.
  You write the notes file before fan-out. You write the report only after the gate in
  step 6 approves it.

Every finding goes in the report as `confirmed` or `accepted`.

| Reference | Covers |
| --- | --- |
| [`../../references/pipeline.md`](../../references/pipeline.md) | Steps 1–5: the plan, the script-written context file and your notes file, the fan-out, the roll call, triage |
| [`../../references/severity.md`](../../references/severity.md) | A / B / C, the tie-breaker, type-aware tiering, deep-block severities |
| [`../../references/delivery.md`](../../references/delivery.md) | Launch rules, the delivery clause, roll call, escalation ladder |
| [`references/rounds.md`](references/rounds.md) | Slot `after-triage`: the `rounds` stage, one more fan-out on the same head |
| [`references/mutation.md`](references/mutation.md) | Slot `after-gate`: the `coverage` stage, its gate question, mutant selection, restore safety, survivors as findings |
| [`references/finalize.md`](references/finalize.md) | Steps 6 and 8: the gate, the FINDINGS.md template, the verdict rubric |

Read each reference the first time that a step needs it, and once only. Relative paths
resolve from this file. If a read fails, use
`${CLAUDE_PLUGIN_ROOT}/references/<name>.md` or
`${CLAUDE_PLUGIN_ROOT}/skills/self-review/references/<name>.md`.

## Steps

1. **Plan.** Resolve the plugin root to a literal path. Then run the plan script in one call:
   `${CLAUDE_PLUGIN_ROOT}/scripts/review-plan.sh --mode self` plus the flags that the user
   passed:
   - `--fix|--feature|--refactor|--chore` → `--type <type>`
   - `--rounds N` → `--budget rounds=N`
   - `--no-coverage` → `--off coverage`
   - `--fresh` → `--fresh`

   If the output has a `guard: refuse:` line, say the reason in one line and stop. Record
   `base`, `head` and `head0` as literal SHAs. When the user gave `$0`, fetch it with `gh`.
   `${CLAUDE_PLUGIN_ROOT}/docs/contracts.md` lists every key of the plan.

   Per pipeline.md, resolve `type: undetermined` yourself. Re-run with `--type` so that the
   skeleton carries the type. Hand any `type_conflict` to the change pass.

   The script writes the context skeleton at the `context:` path from the plan. For a large
   diff, the script also writes the patch files that `diff_prod:` and `diff_tests:` name.
   **Never redirect a `git diff` yourself.** The diff must not pass through your context.
2. **Write the notes file.** Write it with Write at the `notes:` path from the plan, per
   pipeline.md §2, in a message of its own. It holds:
   - Settled facts that you verified beyond the skeleton, at a call or two each. Examples are
     the behavior of a helper, pre-change source, or a consumer elsewhere.
   - Open leads, with one owner pass each.
   - A one-line summary of `$0` when the user gave one.

   A section with nothing to add reads `- none`. Write the file also when every section is
   empty.
3. **Fan out.** In the next message, send one Agent call per pass. Use the `subagent_type`,
   `model` and prompt from the `=== PROMPTS ===` block of the plan, verbatim. Pass no `name`
   (delivery.md). The block already carries the lane of each pass, the deep budget and the
   effort ceiling. A budget of `0` skips the blocks, never the pass.
4. **Assert nothing changed.** `git status --porcelain --untracked-files=no` must still be
   empty. If a pass edited anyway, revert those tracked files with `git checkout -- <path>`.
   Delete the files that the pass created, by path. Keep only the output of the pass as
   findings.

   The context, notes and patch files live in the git directory, so they never appear here.
   Leave every pre-existing untracked file alone.
5. **Roll call and triage.** Do the roll call and triage per pipeline.md, in that order.
   Then run the `after-triage` slot: each stage of the `stages:` block of the plan with
   `slot after-triage`, per the reference file that its line names. The `rounds` stage can
   send you back to step 3.

   The `earlier_findings:` line of the first plan tells you whether an earlier run left
   findings. On a newer head, the passes reconcile them, and triage applies their status.
6. **Gate.** Per finalize.md, print the classified list in chat. Then ask one
   `AskUserQuestion`: write the report, and one question for each stage with `ask yes`. The
   reference file of the stage holds its question. The skill applies nothing either way.
   The gate decides what you produce, not what you change.
7. **After the gate.** Run the `after-gate` slot: each stage with `slot after-gate` that the
   gate approved, per its reference file. Skip a stage with a budget of 0.
8. **Report and verdict.** Per finalize.md, assert that `HEAD` equals `head0` from the plan,
   with nothing unstaged and nothing staged. Write the report when the gate approved it.
   Write the findings file at the end of every run, with the verdict. Also write it when the
   review has no finding, or when the gate declined the report. The next run of this skill
   starts from it. Reply in chat with the type, scale tier, tier counts, the reminder that
   nothing was changed, and the verdict. The verdict is **ready for PR** / **needs more
   work**.

The profile lives in `scripts/lib/policy.sh` and reaches you through the plan. It covers
which passes run, the deep-block budget, and the stages with their budgets. Do not
re-derive it here.
