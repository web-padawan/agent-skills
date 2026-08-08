---
name: self-review
description: Self-review the current branch (or its open PR) before opening or updating a PR. Detects the change type — bug fix, feature, refactor, chore — and runs the matching review profile, then gives every significant change three structured reviews: architectural (observed behavior, risk, consequences, suggestion), boundary (which promise the change makes and to whom), and change-impact analysis (ripple effects, propagation paths, unblock conditions). Never edits code — classifies findings A (must fix before merge) / B (follow-up) / C (taste) and writes a FINDINGS.md report with a ready / needs-work verdict.
argument-hint: "[parent-PR-or-issue-url] [--fix|--feature|--refactor|--chore] [--deep N] [--no-coverage]"
disable-model-invocation: true
allowed-tools: Read, Write, Edit, Glob, Grep, Task, Agent, SendMessage, Skill, AskUserQuestion, Bash(git:*), Bash(gh:*), Bash(yarn:*), Bash(npm:*), Bash(npx:*), Bash(pnpm:*)
---

You are self-reviewing the current branch before it becomes (or updates) a PR. Optional input `$0` is the parent PR or issue this branch was extracted from. Work the stages in order.

Three rules outrank everything else:

- **Never edit code.** Every stage is read-only. The single carve-out is stage 5's coverage mutants: one line at a time, restored with `git checkout -- <path>` before the next, and the stage ends only when `git status --porcelain --untracked-files=no` is empty again. Nothing else in this skill writes to a tracked file. (`Edit` is in `allowed-tools` for that carve-out alone — do not remove it, and do not use it anywhere else.)
- **Never commit or stage.** No commit, amend, push, `git add`, `stash`, `reset --hard`, or `git clean` — ever. `HEAD` and the index end exactly as found.
- **The only files this skill creates are the shared context file and the report**, both in the git-ignored report directory, and the report only after the stage-4 gate approves it.

Every finding ends up in the report as `confirmed` or `accepted`. Nothing is silently dropped.

Detailed instructions live in references — read each one the **first time** a stage needs it, and never twice in a session. They sit next to this file; if a relative read fails, use `${CLAUDE_PLUGIN_ROOT}/skills/self-review/references/<name>.md`.

| Reference | Covers |
| --- | --- |
| [`references/analysis.md`](references/analysis.md) | Stages 1–2a: change inventory, breadth-pass prompts per profile, context file, finding format, severity rubric |
| [`references/deep-review.md`](references/deep-review.md) | Stage 2b: the three per-change reviews — fields, prompts, severity mapping |
| [`references/triage.md`](references/triage.md) | Stages 3–4: verification, classification, the gate |
| [`references/mutation.md`](references/mutation.md) | Stage 5: mutant selection per profile, restore safety, survivors as findings |
| [`references/finalize.md`](references/finalize.md) | Stage 6: FINDINGS.md template, verdict rubric |

## Stage 0 — Setup & guards

- Refuse to run on `main`, `master`, or a `maintenance/*` branch — stop with a one-line message.
- **Tracked files must be clean**: `git status --porcelain --untracked-files=no` empty. If not, stop and ask the user to commit or stash first. Untracked files are fine — never touch them, never stage them. This is not tidiness: stage 5 restores a mutant with `git checkout -- <path>`, which resets the file to the **index**. Because this skill never stages anything, the index equals `HEAD`, so that restore is exact and total. A dirty tree breaks the invariant the carve-out rests on.
- Scope: run `git merge-base origin/main HEAD` and note the resulting SHA — later stages and references write it as `<BASE>`; always substitute the literal SHA (shell variables do not persist between tool calls, and subagents never see them). Changed files = `git diff --name-only <BASE>..HEAD`.
- Record `<HEAD0>` = `git rev-parse HEAD`. Stage 6 asserts `HEAD` still equals it and that the index is still empty — that is the proof nothing was committed or staged.
- **Command map** — record once, used by stage 5. In `vaadin/web-components`: lint `yarn lint`; tests `yarn test --group <package>`; source glob `packages/*/src/*.js`; affected packages = unique `packages/<name>` prefixes of the changed files. In another repo, take lint/test commands from `CLAUDE.md` / `AGENTS.md` / `package.json` scripts and note the equivalent source glob and test-scoping unit.
- **Report location**: `.omc/self-review/<slug>-FINDINGS.md` when `.omc/` is git-ignored (`git check-ignore -q .omc` — true in web-components); otherwise the session scratchpad, so the report never lands in the diff. `<slug>` is the branch name with `/` replaced by `-` — branch names are usually `type/topic`, and using them raw silently creates a directory per prefix. The shared context file sits next to it as `context.md`.
- PR context: `gh pr view --json title,body,url 2>/dev/null` — if a PR exists, its title/body feed the intent check. Fetch `$0` (parent PR/issue) with `gh` when given.

### Change type

Decide the type once, from the first signal that resolves — do not spend a subagent on this:

1. `--fix` / `--feature` / `--refactor` / `--chore` flag.
2. Conventional prefix of the PR title (`fix:`, `feat:`, `refactor:`, `perf:`, `test:`, `docs:`, `chore:`, `build:`, `deps:`).
3. Majority prefix across `git log --format=%s <BASE>..HEAD`.
4. Parent issue labels from `$0` (`bug` → fix, `enhancement` / `feature` → feature).
5. Branch name prefix (`fix/`, `bugfix/`, `feat/`, `refactor/`).
6. Diff shape: new export, public property, method, or `.d.ts` addition → feature; edits inside existing logic plus a test → fix; same behavior moved or renamed → refactor; only tests, docs, or build files → chore.

Take the **first signal that resolves** and stop — that is the declared type, and it is what the profile runs on. `perf:` maps to refactor.

Signals below it may still *disagree*; do not let that silently upgrade the type. Instead, when a lower signal is more demanding than the one that won (`feat` beats `fix` beats `refactor` beats `chore`), keep the declared type and hand the disagreement to the scope pass as an explicit question. A branch whose PR title says `refactor:` while two of its three commits say `fix:` is exactly that case. Two reasons to keep the declared type rather than auto-upgrading: the declared type is what the author is asking reviewers to believe, so reviewing against it is what tests the claim; and the more demanding profile would examine a *different* risk instead of the mislabel itself.

Report the type and the signal that decided it in the stage-6 summary, and treat a wrong-looking type as a `scope` finding — a fix that grows an API is a mislabeled feature, and a refactor that removes public API is a mislabeled breaking change.

### Significant change

The deep review works per change, not per branch, so the changes have to be named first. A hunk in `git diff <BASE>..HEAD` is a **significant change** when it does any of:

1. **Public surface** — adds or alters an export, public property, attribute, method, event, slot, CSS custom property, CSS part, or `.d.ts` entry.
2. **New module** — adds a mixin, controller, class file, or helper that others will import.
3. **Control flow** — changes a decision in existing logic: a new branch, an altered condition, a changed default, a changed early return, a changed lifecycle timing.
4. **Cross-module contract** — changes a data shape, event detail, callback signature, or a mixin's expectation of its host.
5. **Boundary move** — logic extracted, inlined, or relocated between modules or packages.

Never significant: test-only hunks, docs, build/config, pure renames with no call-site semantics change, formatting, comment-only edits, generated files.

**Cap and ranking.** Rank candidates by public-surface reach first, then cross-module reach, then logic density. Take the profile's deep-review budget. Every candidate over the budget goes in the report under `## Not deep-reviewed` with its `file:line` and the reason it ranked below the line — silent truncation is forbidden, the same way stage 5 must list skipped mutant hunks.

A branch with **zero** significant changes (a pure chore, a docs-only edit) skips stage 2b and says so in the summary. That is a valid outcome, not a failure.

### Review profile

The type picks the profile. Numbers are the breadth agents in analysis.md.

| Type | Breadth agents | Deep-review budget | Mutant budget |
| --- | --- | --- | --- |
| **feature** | 1 general · 2 scope · 3 intent · 4 integration · 5 tests · **8 requirements coverage** | 6 significant changes | 15 |
| **fix** | 1 general · 3 intent · 4 integration · 5 tests · **9 root cause & blast radius** | 3, must include the fix's own hunks | 5, concentrated on the fix |
| **refactor** | 1 general · 2 scope · 4 integration · 5 tests · **10 behavior preservation** | 4, weighted to moved boundaries | 10 |
| **chore** | 1 general · 4 integration · 5 tests | 0 — skip stage 2b | none — skip stage 5 |

- `--deep N` overrides the deep-review budget. `--no-coverage` zeroes the mutant budget and skips the gate's coverage question.
- The **slop** quality pass runs for every type, including chore.
- Say in the summary which profile ran, and how many significant changes were deep-reviewed out of how many were found.

## Stage 1 — Change inventory (read-only)

Per analysis.md: write the shared context file, then run **one** `general-purpose` agent that enumerates and ranks significant changes per the rules above. Its output is stage 2b's work list — a small, fast barrier, not a full review.

On a **chore**, skip the agent and record zero significant changes.

## Stage 2 — Analysis (read-only)

The inventory is in hand, so both halves launch in the **same message** and share one barrier.

- **Stage 2a — breadth passes**, per analysis.md: the profile's agents plus the slop pass, the latter wrapped in a subagent so it cannot edit and its instructions stay out of this context.
- **Stage 2b — deep review**, per deep-review.md: the architectural, boundary and CIA reviews for each significant change. Follow its batching rule when the budget exceeds 4 changes.

Read analysis.md's **Delivery** section before launching and follow it exactly — `run_in_background: false`, no `name`, and the delivery clause in every prompt. Those three are what decide whether the findings ever reach you; the defaults silently lose them.

Afterwards assert `git status --porcelain --untracked-files=no` is still empty, and revert anything a pass changed regardless — with no apply stage, any tracked-file modification here is a bug, not a judgement call.

Then run analysis.md's **Delivery check**: roll-call every agent launched, recover the ones that reported nothing by escalating the mechanism, and record each pass as `agent`, `self-run`, or `missing`. A pass that reported nothing has *not* come back clean.

## Stage 3 — Triage & classify (read-only)

Per triage.md: verify every finding against the code, dedup across the breadth passes **and** the three deep-review lenses, assign the final tier, note the suggested one-line fix.

## Stage 4 — Gate

Per triage.md: the classified list in chat, then a single `AskUserQuestion` — write the report, and run the coverage check. Nothing is applied either way; the gate decides what gets produced, not what gets changed.

## Stage 5 — Coverage check (report-only)

Per mutation.md, unless the gate skipped it or the profile has no budget: mutate changed source lines, expect the affected tests to fail, restore each mutant before the next. Survivors are coverage gaps and become findings — this skill never writes the missing test.

## Stage 6 — Report & verdict

Per finalize.md: assert `HEAD` == `<HEAD0>`, nothing unstaged, nothing staged; write the report when the gate approved it; and reply in chat with the profile, the deep-review count, a short summary, tier counts, the reminder that **nothing was changed**, and the verdict: **ready for PR** / **needs more work**.
