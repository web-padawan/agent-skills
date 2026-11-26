---
name: self-review
description: Self-review the current branch (or its open PR) before opening or updating a PR. Detects the change type — bug fix, feature, refactor, chore — and runs three review passes in one parallel batch: a change pass (scope, behavior, the consumers of each public change, logic, fix correctness), a code pass (conventions, reuse, maintainability, comments) and a tests pass. A large feature gets a second round that looks for what the first missed. Never edits code — classifies findings A (must fix before merge) / B (follow-up) / C (taste) and writes a FINDINGS.md fix list with a ready / needs-work verdict. Use on your own branch; not for reviewing someone else's PR (pr-review).
argument-hint: "[parent-PR-or-issue-url] [--fix|--feature|--refactor|--chore] [--rounds N]"
disable-model-invocation: true
allowed-tools: Read, Write, Glob, Grep, Task, Agent, SendMessage, AskUserQuestion, Bash(git:*), Bash(gh:*), Bash(yarn:*), Bash(npm:*), Bash(npx:*), Bash(pnpm:*), Bash(mvn:*), Bash(*/scripts/get-pr-context.sh:*), Bash(*/scripts/review-plan.sh:*), Bash(*/scripts/ab.sh:*)
---

# Self-Review

You review your own current branch before it becomes a PR or updates a PR. The optional
input `$0` is the parent PR or issue that is the source of this branch.

Three rules outrank everything else:

- **Every step is read-only.** Never edit a tracked file.
- **Leave `HEAD` and the index exactly as you found them.** Never run commit, amend, push,
  `git add`, `stash`, `reset --hard`, or `git clean`.
- **This skill creates only the context file, the patch files of a large diff, and the
  report.** The plan writes the first two in the report directory, inside the git directory.

| Reference | Covers |
| --- | --- |
| [`../../references/review-rules.md`](../../references/review-rules.md) | Steps 1 to 5: the plan, facts and leads, the finding line, the roll call, triage, tiers |
| [`references/report.md`](references/report.md) | Steps 7 and 8: the gate, the report, the verdict |

Relative paths resolve from this file. If a read fails, use
`${CLAUDE_PLUGIN_ROOT}/references/<name>.md` or
`${CLAUDE_PLUGIN_ROOT}/skills/self-review/references/<name>.md`.

## Steps

1. **Plan.** Resolve the plugin root to a literal path. Then run the plan in one call:
   `${CLAUDE_PLUGIN_ROOT}/scripts/review-plan.sh --mode self`, plus the flags of the user:
   - `--fix|--feature|--refactor|--chore` → `--type <type>`
   - `--rounds N` as it is

   Follow review-rules.md §1. When the user gave `$0`, fetch it with `gh`.
2. **Facts and leads.** Follow review-rules.md §2. When the user gave `$0`, its one-line
   summary is a Settled fact.
3. **Fan out.** Follow review-rules.md §3 and §4.
4. **Assert nothing changed.** `git status --porcelain --untracked-files=no` must still be
   empty. If a pass edited anyway, restore those tracked files with `git checkout -- <path>`.
   Delete the files that the pass created, by path. Keep only its output as findings. Leave
   every untracked file that existed before alone.
5. **Triage.** Follow review-rules.md §5 and §6. Self-review keeps every tier. A kept finding
   is `confirmed`, or `accepted` when it needs no action: a false positive or a deliberate
   choice. Give each finding an id, `F1`, `F2` and so on.

   On a **fix**, prove the regression test when its test command is cheap. Run the changed
   tests against the production files of the base:
   `${CLAUDE_PLUGIN_ROOT}/scripts/ab.sh --ref <base> --path <prod file> ... -- <test command>`.
   A test that fails on A and passes on B is the regression test. No such test is an A
   finding of the category `tests`.
6. **Second round.** When the plan prints `rounds:` above 1 and this round added a confirmed
   A or B finding, run step 3 again with the same prompts. At the end of each prompt, add:

   ```
   Reported in an earlier round:
   - <file>:<line> <claim>
   ```

   List every finding of the frozen list there, also the accepted ones. Do not run the plan
   again, because the head did not change. Triage the new findings into the same list. Stop
   at the round budget, or after a round with no new A or B finding.
7. **Gate.** Follow report.md. The gate decides what you produce, not what you change.
8. **Report and verdict.** Follow report.md.

The policy lives in `scripts/lib/policy.sh` and reaches you through the plan: the passes,
the round budget, the model and the effort ceiling of each pass. Do not derive it here.
