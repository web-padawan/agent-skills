---
name: self-review
description: Self-review the current branch (or its open PR) before opening or updating a PR. Detects the change type — bug fix, feature, refactor, chore — and runs the matching review profile: a bug fix first has its premise checked against the history of the behavior it changes, then gets five agents; other types give every significant change the three arch-review lenses — architectural, boundary, and change-impact analysis. Never edits code — classifies findings A (must fix before merge) / B (follow-up) / C (taste) and writes a FINDINGS.md report with a ready / needs-work verdict. Use on your own branch; not for reviewing someone else's PR (guided-review, pr-review, adversarial-review) or a single pointed architecture question (arch-review).
argument-hint: "[parent-PR-or-issue-url] [--fix|--feature|--refactor|--chore] [--deep N] [--no-coverage]"
disable-model-invocation: true
allowed-tools: Read, Write, Edit, Glob, Grep, Task, Agent, SendMessage, Skill, AskUserQuestion, Bash(git:*), Bash(gh:*), Bash(yarn:*), Bash(npm:*), Bash(npx:*), Bash(pnpm:*)
---

You are self-reviewing the current branch before it becomes (or updates) a PR. Optional input `$0` is the parent PR or issue this branch was extracted from. Work the stages in order.

Three rules outrank everything else:

- **Never edit code.** Every stage is read-only. The single carve-out is stage 5's coverage mutants: one line at a time, restored with `git checkout -- <path>` before the next, and the stage ends only when `git status --porcelain --untracked-files=no` is empty again. Nothing else in this skill writes to a tracked file. (`Edit` is in `allowed-tools` for that carve-out alone — do not remove it, and do not use it anywhere else.)
- **Never commit or stage.** No commit, amend, push, `git add`, `stash`, `reset --hard`, or `git clean` — ever. `HEAD` and the index end exactly as found.
- **The only files this skill creates are the shared context file and the report**, both in the git-ignored report directory, and the report only after the stage-4 gate — or, on a premise-stopped fix, the premise-stop question that stands in for it — approves it.

Every finding ends up in the report as `confirmed` or `accepted`. Nothing is silently dropped.

Detailed instructions live in references — read each one the **first time** a stage needs it, and never twice in a session. `analysis.md`, `fix-profile.md`, `triage.md`, `mutation.md` and `finalize.md` sit next to this file (fallback `${CLAUDE_PLUGIN_ROOT}/skills/self-review/references/<name>.md`); `significance.md` and `lenses.md` belong to the sibling `arch-review` skill (fallback `${CLAUDE_PLUGIN_ROOT}/skills/arch-review/references/<name>.md`).

| Reference | Covers |
| --- | --- |
| [`references/analysis.md`](references/analysis.md) | Stages 1–2: change inventory, breadth-pass prompts per profile (incl. agent 11's procedure), deep-review batching, context file, finding format, severity rubric |
| [`references/fix-profile.md`](references/fix-profile.md) | Fix only: launch order, premise decision rules, the premise-stop gate, five-agent cap, single-lens choice, size check |
| [`../arch-review/references/significance.md`](../arch-review/references/significance.md) | What counts as a significant change, ranking, the stage-1 inventory contract |
| [`../arch-review/references/lenses.md`](../arch-review/references/lenses.md) | Stage 2b: the lens agent table, severity mapping, block→finding rules |
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

### Significant changes

The deep review works per change, not per branch. What qualifies, how candidates are ranked, and the inventory contract all live in [`../arch-review/references/significance.md`](../arch-review/references/significance.md) — stage 1 carries its rules verbatim. In short: public surface, new modules, control-flow decisions, cross-module contracts, and boundary moves qualify; tests, docs, config, formatting never do. Candidates over the profile's budget are listed in the report under `## Not deep-reviewed`, never silently dropped. A branch with **zero** significant changes skips stage 2b and says so in the summary — a valid outcome, not a failure.

### Review profile

The type picks the profile. Numbers are the breadth agents in analysis.md.

| Type | Breadth agents | Deep-review budget | Mutant budget |
| --- | --- | --- | --- |
| **feature** | 1 general · 2 scope · 3 intent · 4 integration · 5 tests · **8 requirements coverage** | 6 significant changes | 15 |
| **fix** | 1 general · 5 tests · **9 root cause & blast radius** · one lens on the fix's own hunks — plus **11 premise & history** before Stage 1; **5 agents total, hard cap** | 1 change, 1 lens: the fix's own hunks | 5, concentrated on the fix |
| **refactor** | 1 general · 2 scope · 4 integration · 5 tests · **10 behavior preservation** | 4, weighted to moved boundaries | 10 |
| **chore** | 1 general · 4 integration · 5 tests | 0 — skip stage 2b | none — skip stage 5 |

- `--deep N` overrides the deep-review budget. `--no-coverage` zeroes the mutant budget and skips the gate's coverage question.
- The **slop** quality pass runs for every type except **fix**, where the comment policy folds into agent 1 instead.
- Say in the summary which profile ran, and how many significant changes were deep-reviewed out of how many were found.

### Fix profile — premise first, five agents total

The fix pipeline differs end to end — read [`references/fix-profile.md`](references/fix-profile.md) before Stage 1 on a fix. In short:

- **Agent 11 (premise & history) runs before Stage 1**, after the context file is written, and answers one question: does the project already have a decision about this behavior? `sound` / `unverified` → continue. **`contradicted` → stop the review**: report the citation and ask the user with `AskUserQuestion` — that question stands in for the stage-4 gate, and Stages 1–5 never run.
- **Five agents total, hard cap**: agent 11, then a single stage-2 message of **four** — agent 1 (carrying the folded scope, intent, integration and slop questions), 5, 9, and one lens on the fix's own hunks, chosen per fix-profile.md.
- No inventory agent and no separate slop pass; fix-profile.md's size check replaces the enumerator.

## Stage 1 — Change inventory (read-only)

Per analysis.md: write the shared context file, then run **one** `agent-skills:change-enumerator` agent that enumerates and ranks significant changes. Its output is stage 2b's work list — a small, fast barrier, not a full review.

On a **chore**, skip the agent and record zero significant changes. On a **fix**, skip it too:
the one deep-reviewed change is the fix's own production hunks, taken straight from
`git diff <BASE>..HEAD`, so there is nothing for an enumerator to rank.

## Stage 2 — Analysis (read-only)

The inventory is in hand, so both halves launch in the **same message** and share one barrier.

- **Stage 2a — breadth passes**, per analysis.md's pass table: the profile's `agent-skills:*` reviewer agents plus the slop pass (`agent-skills:comment-reviewer`) — every pass's contract lives in its agent definition, so prompts carry only the context file path, the table's run-specific facts, and the delivery clause.
- **Stage 2b — deep review**: the three `agent-skills:lens-*` agents per significant change — contracts in the agent definitions, severity mapping in [`../arch-review/references/lenses.md`](../arch-review/references/lenses.md), batching and prompt shape per analysis.md's **Stage 2b** section.

On a **fix** this is a single message of **four** agents — breadth passes 1, 5 and 9, plus the
one lens — and the premise check has already run and returned `sound` or `unverified` (on
`contradicted` the run stopped before this stage; see fix-profile.md).

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
