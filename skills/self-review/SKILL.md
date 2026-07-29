---
name: self-review
description: Self-review the current branch (or its open PR) before opening/updating a PR — general review, scope, direction, simplification, integration, tests with mutation check, slop cleanup. Applies fixes in a single commit and writes a findings report with a ready / needs-work verdict.
argument-hint: "[parent-PR-or-issue-url]"
disable-model-invocation: true
allowed-tools: Read, Write, Edit, Glob, Grep, Task, Skill, Bash(git:*), Bash(gh:*), Bash(yarn:*), Bash(npm:*), Bash(npx:*), Bash(pnpm:*)
---

You are self-reviewing the current branch before it becomes (or updates) a PR. Optional input `$0` is the parent PR or issue this branch was extracted from. Work the phases in order. **Every finding must end up in the report marked `fixed` or `accepted` — nothing gets silently dropped.**

Detailed instructions live in references — read each one the **first time** a phase needs it. They stay in context: on later runs in the same session, do not re-read them. They sit next to this file; if a relative read fails, use `${CLAUDE_PLUGIN_ROOT}/skills/self-review/references/<name>.md`.

| Reference | Covers |
| --- | --- |
| [`references/analysis.md`](references/analysis.md) | Phases 1–2: agent prompts, finding format |
| [`references/fixes.md`](references/fixes.md) | Phase 3: triage, simplify, slop, comment policy |
| [`references/mutation.md`](references/mutation.md) | Phase 4: mutant selection, budget, breaking tests |
| [`references/finalize.md`](references/finalize.md) | Phases 3 & 5: commit protocol, report template, verdict rubric |

## Phase 0 — Setup & guards

- Refuse to run on `main`, `master`, or a `maintenance/*` branch — stop with a one-line message.
- Require a clean working tree (`git status --porcelain` empty). If dirty, stop and ask the user to commit or stash first.
- Scope: run `git merge-base origin/main HEAD` and note the resulting SHA — later phases and references write it as `<BASE>`; always substitute the literal SHA (shell variables do not persist between tool calls, and subagents never see them). Changed files = `git diff --name-only <BASE>..HEAD`.
- **Command map** — record once, reuse in phases 3–4. In `vaadin/web-components`: lint `yarn lint`; tests `yarn test --group <package>`; source glob `packages/*/src/*.js`; affected packages = unique `packages/<name>` prefixes of the changed files. In another repo, take lint/test commands from `CLAUDE.md` / `AGENTS.md` / `package.json` scripts and note the equivalent source glob and test-scoping unit.
- **Report location**: `.omc/self-review/<branch>.md` when `.omc/` is git-ignored (`git check-ignore -q .omc` — true in web-components); otherwise use the session scratchpad, so the report never lands in the diff.
- PR context: `gh pr view --json title,body,url 2>/dev/null` — if a PR exists, its title/body feed the direction check. Fetch `$0` (parent PR/issue) with `gh` when given.
- Record the current head: `git rev-parse HEAD` — the skill adds **at most one** commit on top of it.

## Phase 1 — Parallel analysis (read-only, original diff)

Launch all four agents **in one message** per analysis.md:

1. **General review** — `oh-my-claudecode:code-reviewer`
2. **Scope check** — splittability, unrelated changes, parent-PR fit
3. **Direction check** — implemented approach vs original idea, "plausible nonsense" hunt
4. **Integration check** — conventions-doc compliance, naming, method ordering across files

If OMC agents are unavailable, run the same prompt on a `general-purpose` agent instead. Collect findings in the shared format from analysis.md.

## Phase 2 — Test review

`oh-my-claudecode:test-engineer` reviews changed/added tests per analysis.md: assertions meaningful, no reliance on implementation detail or private APIs.

## Phase 3 — Apply fixes

Per fixes.md: triage every finding (verify in code → `fix` or `accepted` + reason), apply fixes, then `Skill(simplify)`, then `Skill(oh-my-claudecode:ai-slop-cleaner)`, then the comment policy pass. Gate: lint and the affected tests green, using the phase-0 command map. Commit **once** per finalize.md.

## Phase 4 — Mutation check

Per mutation.md: mutate changed source lines one hunk at a time, expect the affected tests to fail, restore. Surviving mutant = coverage gap → write a breaking test. Budget: 15 mutants.

## Phase 5 — Finalize

Per finalize.md: amend new tests into the phase-3 commit (or create the single commit if phase 3 made none), write the report to the phase-0 report location, reply in chat with a short summary + verdict: **ready for PR** / **needs more work**.
