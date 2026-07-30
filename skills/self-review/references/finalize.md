# Phase 7 — Report & verdict

## End-state checks

- `git rev-parse HEAD` == `<HEAD0>` from phase 0 — proof nothing was committed. If it differs, say so loudly at the top of the chat reply.
- `git diff --name-only` empty — nothing unstaged, no mutant residue.
- `git diff --staged --stat` — the change set the user is about to commit. Show this summary in chat.
- Pre-existing untracked files are untouched and unstaged.

Never commit, amend, push, `stash`, `reset --hard`, or `git clean`. The user commits.

## Report — phase-0 report location (`.omc/self-review/<branch>.md` in web-components)

````markdown
# Self-review: <branch> — <date>

**Verdict: ready for PR | needs more work**
Type: <feature | fix | refactor | chore> (signal: <what decided it>) · architecture pass: ran | skipped
Applied: <tiers approved> · changes **staged, not committed**

| Tier            | Fixed | Deferred | Accepted |
| --------------- | ----- | -------- | -------- |
| A critical      |       |          |          |
| B follow-up     |       |          |          |
| C taste         |       |          |          |

<one paragraph: what was reviewed, what changed, what remains>

## General review
- [A][fixed] packages/foo/src/foo.js:42 — <claim>
- [B][deferred] <file>:<line> — <claim> — <why deferred>
- [C][accepted] <file>:<line> — <claim> — <why it is not a problem>

## Architecture
## Scope
## Intent
## Integration
## Tests
## Simplification
## Slop

## Follow-ups
- [B] <file>:<line> — <claim> — <intended fix>

## Commit
Suggested subject: `<type>: <summary>` (repo commit rules — `.claude/rules/commits-and-prs.md` in vaadin/web-components, else the style of recent `git log`)
Review with `git diff --staged`, then commit. `git reset` unstages without losing the edits.
````

- Every finding from every phase appears under its category, tagged `[tier]` and `[status]`. Statuses: `fixed` (applied), `deferred` (real, not applied now), `accepted` (no action needed — false positive or deliberate choice).
- Add the profile's own sections after the shared ones: **feature** → `## API design`, `## Requirements coverage`; **fix** → `## Root cause & blast radius`; **refactor** → `## Behavior preservation`.
- Omit sections whose agent the profile did not run. Empty category → `- none`.
- Coverage stats line under **Tests**: `N mutants, K killed, S survived (T tests added), skipped: <hunks or none>`. On a **fix**, prefix it with the whole-fix revert result: `regression test: <name> fails without the fix | none fails without the fix`.
- **Follow-ups** repeats every `deferred` finding as a paste-ready list for the follow-up issue or PR.
- The report itself is never committed — it lives in the git-ignored phase-0 location.

## Verdict rubric

**needs more work** when any of:

- an A finding is unresolved — `deferred`, or approved but not applied
- lint or the affected tests fail
- a surviving A-tier coverage gap has no test
- **fix**: no test fails when the whole fix is reverted, and none was added
- **feature**: a stated requirement is unimplemented, or new public API ships with a finding that a later fix could not correct without a breaking change
- **refactor**: an observable behavior change is unexplained

Otherwise **ready for PR**. Unresolved B and C findings never block; they live under Follow-ups.

The verdict describes the **staged** tree, not a commit.

## Chat reply

Verdict + detected type and profile + tier counts + 3–5 essential bullets + "staged, not committed" + report path. Name any deferred A finding explicitly. Do not restate the full report.
