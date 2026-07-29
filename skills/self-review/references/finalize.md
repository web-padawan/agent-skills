# Phases 3 & 5 — Commit, report, verdict

## Commit protocol

- At most **one** new commit on top of the head recorded in phase 0. Verify at the end: `git rev-list <recorded-head>..HEAD --count` ≤ 1 (== 1 whenever anything changed).
- Phase 3 creates it with all fixes; phase 5 amends breaking tests in (`git commit --amend --no-edit`). If phase 3 made no commit but phase 4 produced new tests, phase 5 creates the single commit instead of amending.
- Message per the repo's commit rules — `.claude/rules/commits-and-prs.md` in vaadin/web-components, else the style of recent `git log`. Subject describes the review fixes, e.g. `refactor: address self-review findings`. Never push, never open a PR.
- Nothing to fix at all → no commit; say so in the summary.
- The report is never committed — it goes to the git-ignored location chosen in phase 0.

## Report — phase-0 report location (`.omc/self-review/<branch>.md` in web-components)

```markdown
# Self-review: <branch> — <date>

**Verdict: ready for PR | needs more work**

<one-paragraph summary: what was reviewed, what changed, what remains>

## General review
- [fixed] packages/foo/src/foo.js:42 — <claim>
- [accepted] <file>:<line> — <claim> — <reason>

## Scope
## Direction
## Simplification
## Integration
## Tests
## Slop
```

- Every finding from every phase appears under its category with `[fixed]` or `[accepted]` — including simplify/slop-cleaner changes and surviving-mutant tests.
- Empty category → `- none`.
- Mutation stats line under **Tests**: `N mutants, K killed, S survived (S tests added), skipped: <hunks or none>`.

## Verdict rubric

**needs more work** when any of:
- unresolved `high` finding in **any** category (accepted with reason ≠ resolved for high severity — only false positives may be accepted at high)
- surviving mutant without a new breaking test and without an `accepted` rationale
- lint or the affected tests failing
- scope check recommends a split and the user has not decided yet

Otherwise **ready for PR**.

## Chat reply

Verdict + 3–5 essential bullets + commit SHA + pointer to the report file. Do not restate the full report.
