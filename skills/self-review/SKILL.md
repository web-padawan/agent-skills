---
name: self-review
description: Self-review the current branch (or its open PR) before opening or updating a PR — general, scope, direction, integration, tests with a coverage check, simplification and slop passes, plus an optional architecture pass on bigger diffs. Classifies findings A (must fix before merge) / B (follow-up) / C (taste), asks before applying anything, and leaves approved fixes staged but never committed, with a findings report and a ready / needs-work verdict.
argument-hint: "[parent-PR-or-issue-url] [--arch|--no-arch]"
disable-model-invocation: true
allowed-tools: Read, Write, Edit, Glob, Grep, Task, Skill, AskUserQuestion, Bash(git:*), Bash(gh:*), Bash(yarn:*), Bash(npm:*), Bash(npx:*), Bash(pnpm:*)
---

You are self-reviewing the current branch before it becomes (or updates) a PR. Optional input `$0` is the parent PR or issue this branch was extracted from. Work the phases in order.

Two rules outrank everything else:

- **Nothing is applied without approval.** Phases 0–4 are read-only; the only edits allowed are the ones approved at the phase-4 gate.
- **Never commit.** The run ends with approved fixes **staged**, `HEAD` untouched, so the user commits. No commit, amend, push, `stash`, `reset --hard`, or `git clean` — ever.

Every finding ends up in the report as `fixed`, `deferred`, or `accepted`. Nothing is silently dropped.

Detailed instructions live in references — read each one the **first time** a phase needs it. They stay in context: on later runs in the same session, do not re-read them. They sit next to this file; if a relative read fails, use `${CLAUDE_PLUGIN_ROOT}/skills/self-review/references/<name>.md`.

| Reference | Covers |
| --- | --- |
| [`references/analysis.md`](references/analysis.md) | Phases 1–2: agent prompts, finding format, severity rubric, comment policy |
| [`references/triage.md`](references/triage.md) | Phases 3–4: verification, classification, the approval gate |
| [`references/apply.md`](references/apply.md) | Phase 5: applying approved fixes, staging |
| [`references/mutation.md`](references/mutation.md) | Phase 6: mutant selection, restore safety, survivors |
| [`references/finalize.md`](references/finalize.md) | Phase 7: report template, verdict rubric |

## Phase 0 — Setup & guards

- Refuse to run on `main`, `master`, or a `maintenance/*` branch — stop with a one-line message.
- **Tracked files must be clean**: `git status --porcelain --untracked-files=no` empty. If not, stop and ask the user to commit or stash first. Untracked files are fine — never touch them, never stage them.
- Scope: run `git merge-base origin/main HEAD` and note the resulting SHA — later phases and references write it as `<BASE>`; always substitute the literal SHA (shell variables do not persist between tool calls, and subagents never see them). Changed files = `git diff --name-only <BASE>..HEAD`.
- Record `<HEAD0>` = `git rev-parse HEAD`. Phase 7 asserts `HEAD` still equals it — that is the proof nothing was committed.
- **Command map** — record once, reuse in phases 5–6. In `vaadin/web-components`: lint `yarn lint`; tests `yarn test --group <package>`; source glob `packages/*/src/*.js`; affected packages = unique `packages/<name>` prefixes of the changed files. In another repo, take lint/test commands from `CLAUDE.md` / `AGENTS.md` / `package.json` scripts and note the equivalent source glob and test-scoping unit.
- **Report location**: `.omc/self-review/<branch>.md` when `.omc/` is git-ignored (`git check-ignore -q .omc` — true in web-components); otherwise the session scratchpad, so the report never lands in the diff.
- **Architecture pass** — decide once: on with `--arch`, off with `--no-arch`, otherwise on when the branch is big or shape-changing, i.e. **any** of: ≥ 6 changed source files; ≥ 300 changed source lines (`git diff --shortstat <BASE>..HEAD`, tests and snapshots excluded); a new module added (mixin, controller, class file); public API touched (new or changed export, new public property or method, `.d.ts` change). Off for single-file fixes and test-only branches. Say in the summary whether it ran.
- PR context: `gh pr view --json title,body,url 2>/dev/null` — if a PR exists, its title/body feed the direction check. Fetch `$0` (parent PR/issue) with `gh` when given.

## Phase 1 — Parallel analysis (read-only)

Launch every applicable agent **in one message** per analysis.md:

1. **General review** — `oh-my-claudecode:code-reviewer`
2. **Scope check** — splittability, unrelated changes, parent-PR fit
3. **Direction check** — implemented approach vs original idea, "plausible nonsense" hunt
4. **Integration check** — conventions-doc compliance, naming, member ordering across files
5. **Test review** — `oh-my-claudecode:test-engineer`
6. **Architecture check** — `oh-my-claudecode:architect`, only when phase 0 turned it on: which new logic will be expensive to change in six months, and the cheapest way to lower that cost

If OMC agents are unavailable, run the same prompts on `general-purpose` agents instead.

## Phase 2 — Quality passes (reviewer-only)

Per analysis.md: `Skill(oh-my-claudecode:ai-slop-cleaner)` in reviewer-only mode and `Skill(simplify)` instructed to report without editing. Afterwards assert tracked files are still clean and revert anything a pass changed regardless — their output is findings, not edits.

## Phase 3 — Triage & classify (read-only)

Per triage.md: verify every finding against the code, dedup, assign the final tier — **A** must fix before merge, **B** should fix soon but a follow-up PR is fine, **C** taste. Note the intended one-line fix for each. Still no edits.

## Phase 4 — Approval gate

Per triage.md: show the classified list in chat, then a single `AskUserQuestion` — which tiers to apply now, and whether the coverage check may write tests for gaps it finds. Nothing not approved here gets applied.

## Phase 5 — Apply approved fixes

Per apply.md: apply the approved findings A → B → C, keep lint and the affected tests green (phase-0 command map), then **stage exactly the paths you changed** (`git add <path>` — never `-A`). Do not commit.

## Phase 6 — Coverage check

Per mutation.md, unless the gate skipped it: mutate changed source lines one hunk at a time, expect the affected tests to fail, restore from the index. A surviving mutant is a coverage gap — write a breaking test when the gate authorized it, otherwise record it. Budget: 15 mutants.

## Phase 7 — Report & verdict

Per finalize.md: assert `HEAD` == `<HEAD0>` and nothing is unstaged, write the report to the phase-0 location, and reply in chat with a short summary, the tier counts, the reminder that changes are staged and uncommitted, and the verdict: **ready for PR** / **needs more work**.
