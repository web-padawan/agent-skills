# Gate, report, verdict

## Gate (step 7)

Print the frozen list of triage in chat, by tier. Never print the reports of the passes.

```
Type: fix (signal: branch name prefix) · Scale: lite (78 lines, 4 files) · Rounds: 1

A (must fix before merge): 1
  F2 packages/foo/src/foo.js:42 — <claim> → <fix>
B (follow-up is fine): 3
  F1 ...
C (taste): 5
Accepted: 2
```

When there is at least one A, say this first: this skill applies nothing, so the verdict will
be *needs more work* whatever the answer.

Then ask one `AskUserQuestion` with the header `Report`: "Write the findings report?"

- `Yes — write FINDINGS.md` *(Recommended)*. Name the `report:` path of the plan.
- `No — chat summary only`.

On the trivial tier with no A finding, recommend `No — chat summary only`. Skip the question
when the list is empty. A free answer wins over the options. When the author disputes a
finding, by id or by claim, set it to `accepted` with the reason of the author.

## End state (step 8)

Make three assertions:

- `git rev-parse HEAD` equals `head0` of the plan.
- `git diff --name-only` is empty.
- `git diff --staged --name-only` is empty.

If one fails, say so at the top of the chat reply, before anything else.

## Report

Write the report at the `report:` path of the plan when the gate approved it. Never commit
it. Otherwise give the same list in the chat reply. Never lose a finding.

````markdown
# Self-review: <branch> — <date>

**Verdict: ready for PR | needs more work**
Head: `<head>` · Type: <type> (<signal>) · Scale: <tier> (<N> lines, <M> files) · Rounds: <n>
Passes: change ✅ · code ✅ · tests ⚠️ self-run

## A — must fix before merge
- F2 `packages/foo/src/foo.js:42` [behavior] <claim> → <fix>

## B — follow-up is fine
- F1 `<file>:<line>` [tests] <claim> → <fix> — verified: <how>

## C — taste
- F5 `<file>:<line>` [comments] <claim> → <fix>

## Accepted
- F7 `<file>:<line>` [logic] <claim> — <why it needs no action>
````

- Order the findings of each tier by severity. Omit an empty tier.
- Add `[orchestrator]` to a finding that you raised yourself, and `[self-run]` to a finding of
  a self-run pass.
- When the verification of a claim is not obvious from the claim, end it with
  `— verified: <how>`: the command, the browser, the commit that you read.
- On a fix, add one line under the header: `Regression test: <name> fails without the fix`,
  or `Regression test: none fails without the fix`, or `Regression test: not checked`.

## Verdict

**needs more work** when any of these holds:

- A confirmed A finding exists. This skill changes nothing, so an A stays open.
- **fix**: no test fails when the fix is reverted.
- **feature**: a stated requirement is not implemented.
- **refactor**: an observable behavior change has no explanation.
- The change or the code pass is `missing`. Then nothing examined what the change does or how
  the diff reads.

Otherwise **ready for PR**. B and C findings never block. The verdict describes `HEAD` as it
stands.

## Chat reply

Give the verdict, the type and the scale, the tier counts, 3 to 5 essential bullets,
"nothing was changed", and the report path. Name every confirmed A finding. Name every pass
that was `self-run` or `missing`, because reduced coverage changes what the verdict is worth.
