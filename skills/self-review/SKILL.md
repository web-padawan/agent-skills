---
name: self-review
description: Self-review the current branch (or its open PR) before opening or updating a PR. Detects the change type — bug fix, feature, refactor, chore — and runs the matching review profile: a feature gets API-design, requirements-coverage and architecture passes, a fix gets root-cause and blast-radius passes plus a regression-test check, a chore gets a short pass. Classifies findings A (must fix before merge) / B (follow-up) / C (taste), asks before applying anything, and leaves approved fixes staged but never committed, with a findings report and a ready / needs-work verdict.
argument-hint: "[parent-PR-or-issue-url] [--fix|--feature|--refactor|--chore] [--arch|--no-arch]"
disable-model-invocation: true
allowed-tools: Read, Write, Edit, Glob, Grep, Task, Skill, AskUserQuestion, Bash(git:*), Bash(gh:*), Bash(yarn:*), Bash(npm:*), Bash(npx:*), Bash(pnpm:*)
---

You are self-reviewing the current branch before it becomes (or updates) a PR. Optional input `$0` is the parent PR or issue this branch was extracted from. Work the phases in order.

Two rules outrank everything else:

- **Nothing is applied without approval.** Phases 0–4 are read-only; the only edits allowed are the ones approved at the phase-4 gate.
- **Never commit.** The run ends with approved fixes **staged**, `HEAD` untouched, so the user commits. No commit, amend, push, `stash`, `reset --hard`, or `git clean` — ever.

Every finding ends up in the report as `fixed`, `deferred`, or `accepted`. Nothing is silently dropped.

Detailed instructions live in references — read each one the **first time** a phase needs it, and never twice in a session. They sit next to this file; if a relative read fails, use `${CLAUDE_PLUGIN_ROOT}/skills/self-review/references/<name>.md`.

| Reference | Covers |
| --- | --- |
| [`references/analysis.md`](references/analysis.md) | Phases 1–2: agent prompts per profile, context file, finding format, severity rubric |
| [`references/triage.md`](references/triage.md) | Phases 3–4: verification, classification, the approval gate |
| [`references/apply.md`](references/apply.md) | Phase 5: applying approved fixes, staging |
| [`references/mutation.md`](references/mutation.md) | Phase 6: mutant selection per profile, restore safety, survivors |
| [`references/finalize.md`](references/finalize.md) | Phase 7: report template, verdict rubric |

## Phase 0 — Setup & guards

- Refuse to run on `main`, `master`, or a `maintenance/*` branch — stop with a one-line message.
- **Tracked files must be clean**: `git status --porcelain --untracked-files=no` empty. If not, stop and ask the user to commit or stash first. Untracked files are fine — never touch them, never stage them.
- Scope: run `git merge-base origin/main HEAD` and note the resulting SHA — later phases and references write it as `<BASE>`; always substitute the literal SHA (shell variables do not persist between tool calls, and subagents never see them). Changed files = `git diff --name-only <BASE>..HEAD`.
- Record `<HEAD0>` = `git rev-parse HEAD`. Phase 7 asserts `HEAD` still equals it — that is the proof nothing was committed.
- **Command map** — record once, reuse in phases 5–6. In `vaadin/web-components`: lint `yarn lint`; tests `yarn test --group <package>`; source glob `packages/*/src/*.js`; affected packages = unique `packages/<name>` prefixes of the changed files. In another repo, take lint/test commands from `CLAUDE.md` / `AGENTS.md` / `package.json` scripts and note the equivalent source glob and test-scoping unit.
- **Report location**: `.omc/self-review/<branch>.md` when `.omc/` is git-ignored (`git check-ignore -q .omc` — true in web-components); otherwise the session scratchpad, so the report never lands in the diff.
- PR context: `gh pr view --json title,body,url 2>/dev/null` — if a PR exists, its title/body feed the intent check. Fetch `$0` (parent PR/issue) with `gh` when given.

### Change type

Decide the type once, from the first signal that resolves — do not spend a subagent on this:

1. `--fix` / `--feature` / `--refactor` / `--chore` flag.
2. Conventional prefix of the PR title (`fix:`, `feat:`, `refactor:`, `perf:`, `test:`, `docs:`, `chore:`, `build:`, `deps:`).
3. Majority prefix across `git log --format=%s <BASE>..HEAD`.
4. Parent issue labels from `$0` (`bug` → fix, `enhancement` / `feature` → feature).
5. Branch name prefix (`fix/`, `bugfix/`, `feat/`, `refactor/`).
6. Diff shape: new export, public property, method, or `.d.ts` addition → feature; edits inside existing logic plus a test → fix; same behavior moved or renamed → refactor; only tests, docs, or build files → chore.

Mixed signals resolve to the more demanding type: `feat` beats `fix` beats `refactor` beats `chore`. `perf:` maps to refactor. Report the type and the signal that decided it in the phase-7 summary, and treat a wrong-looking type as a `scope` finding — a fix that grows an API is a mislabeled feature.

### Review profile

The type picks the profile. Numbers are the phase-1 agents in analysis.md.

| Type | Phase-1 agents | Architecture pass | Mutant budget |
| --- | --- | --- | --- |
| **feature** | 1 general · 2 scope · 3 intent · 4 integration · 5 tests · 6 arch · **7 API design** · **8 requirements coverage** | always on | 15 |
| **fix** | 1 general · 3 intent · 4 integration · 5 tests · **9 root cause & blast radius** | off unless it adds a module or public API | 5, concentrated on the fix |
| **refactor** | 1 general · 2 scope · 4 integration · 5 tests · **10 behavior preservation** | on when modules move or split | 10 |
| **chore** | 1 general · 4 integration · 5 tests | off | none — skip phase 6 |

- `--arch` / `--no-arch` overrides the architecture column. For **fix** and **refactor** the default turns on when the branch is big or shape-changing: ≥ 6 changed source files, ≥ 300 changed source lines (`git diff --shortstat <BASE>..HEAD`, tests and snapshots excluded), a new module (mixin, controller, class file), or touched public API.
- The phase-2 quality passes (slop, simplification) run for every type except **chore**, where only slop runs.
- Say in the summary which profile ran and whether the architecture pass was part of it.

## Phase 1 — Parallel analysis (read-only)

Per analysis.md: write the shared context file first, then launch the profile's agents **and** the phase-2 passes in **one message**. If OMC agents are unavailable, run the same prompts on `general-purpose` agents.

## Phase 2 — Quality passes (reviewer-only)

Per analysis.md: the slop and simplification passes, wrapped in subagents so they cannot edit and their instructions stay out of this context. Afterwards assert tracked files are still clean and revert anything a pass changed regardless — their output is findings, not edits.

## Phase 3 — Triage & classify (read-only)

Per triage.md: verify every finding against the code, dedup, assign the final tier, note the intended one-line fix. Still no edits.

## Phase 4 — Approval gate

Per triage.md: the classified list in chat, then a single `AskUserQuestion`. Nothing not approved here gets applied.

## Phase 5 — Apply approved fixes

Per apply.md: apply A → B → C, keep lint and the affected tests green, then stage exactly the paths you changed. Do not commit.

## Phase 6 — Coverage check

Per mutation.md, unless the gate skipped it or the profile has no budget: mutate changed source lines, expect the affected tests to fail, restore from the index. Survivors are coverage gaps.

## Phase 7 — Report & verdict

Per finalize.md: assert `HEAD` == `<HEAD0>` and nothing is unstaged, write the report, and reply in chat with the profile, a short summary, tier counts, the reminder that changes are staged and uncommitted, and the verdict: **ready for PR** / **needs more work**.
