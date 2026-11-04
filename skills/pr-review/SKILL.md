---
name: pr-review
description: Review a GitHub pull request from someone else. Explain its goal with a concrete example, check the intake facts (linked issue and labels, the packages that import the changed code, fork origin, the claims of the body) and whether the change is worth a review now, then, after you confirm, run the plugin's reviewer agents or a quick single-context review, and post only what you select as inline Conventional Comments, one summary review, or a drafted reply. Use when asked to review this PR, walk me through a PR, review a contribution, an external, community, fork or AI-generated PR, triage a PR before review, do a full review of a pull request, or review and post comments on a PR. Not for your own branch before it has a PR (self-review).
argument-hint: "[PR number or URL, or blank to auto-detect from current branch] [--deep N] [--quick]"
allowed-tools: Read, Write, Edit, Glob, Grep, Task, Agent, SendMessage, AskUserQuestion, Bash(git:*), Bash(gh:*), Bash(yarn:*), Bash(npm:*), Bash(npx:*), Bash(pnpm:*), Bash(*/scripts/gh-context.sh:*), Bash(*/scripts/get-pr-context.sh:*), Bash(*/scripts/review-plan.sh:*), Bash(*/scripts/post-review.sh:*), Bash(*/scripts/post-comment.sh:*)
---

# PR Review

Review a PR that someone else wrote. **Understand first, review second, post last.** The
skill augments a human review. It never replaces it. It requires the `gh` CLI. Parallel
read-only plugin agents run the full review. They read a context file that a script writes.
You read the plan, not the diff. `yarn`, `npm`, `npx` and `pnpm` are allowed only for the
revert check of a same-repo PR.

| Reference | Covers |
| --- | --- |
| [`references/understand.md`](references/understand.md) | Step 2: the explanation and the intake card |
| [`references/intake.md`](references/intake.md) | The verdicts, the hint table, the claims of the body |
| [`references/quick.md`](references/quick.md) | The single-context review, also the fallback |
| [`../../references/pipeline.md`](../../references/pipeline.md) | The plan, the context and notes files, the fan-out, the roll call, triage |
| [`../../references/severity.md`](../../references/severity.md) | A / B / C, type-aware tiering, the rendering table |
| [`../../references/delivery.md`](../../references/delivery.md) | Launch rules, the delivery clause, roll call, escalation ladder |
| [`../../references/comment-guidelines.md`](../../references/comment-guidelines.md) | Comment tone, replies by verdict, posting. Read before step 6 |
| [`references/present.md`](references/present.md) | Step 6: the chat template, the verdict rule, the gate |

Relative paths resolve from this file. If a read fails, use
`${CLAUDE_PLUGIN_ROOT}/references/<name>.md`.

## Hard rules

- **Post nothing without explicit confirmation.** Never approve, request changes, resolve
  threads, close a PR or change labels.
- **A fork head is untrusted code.** Never check it out. Never run `yarn`, `npm`, `npx`,
  `pnpm`, `node` or a script of the PR on it. The plan refuses a checked-out fork head. The
  Bash guard of the plugin holds the passes to read commands while the fork marker is fresh.
- **Gate before fan-out.** Steps 1 and 2 are cheap. The reviewer decides at step 3 whether
  the expensive step runs.

## Steps

### 1. Plan

Make one call. Resolve the plugin root to a literal path. Send the context file to the
scratchpad:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/review-plan.sh --mode pr [--pr <number-or-url>] [--deep N] \
  --context-out <scratchpad>/pr-<number>-context.md
```

Read the plan top to bottom and act on every `hint:`. Record `base` and `head` as literals.
Read `fork:`, `intake:`, `ci:` and `existing_comments:` first. A red check is an A finding on
its own. A green check retires that class of finding. A review bot in a `hint:` has probably
taken the cheap findings.

### 2. Understand

Follow [`references/understand.md`](references/understand.md): problem, change, mechanism,
example and scope. On a fork PR or a PR from outside the team, add the intake card.

### 3. Gate

Ask one `AskUserQuestion`, header `Review`: "How should I continue?" Put the default of the
verdict first, per [`references/intake.md`](references/intake.md):

- `Full review`: steps 4 to 7.
- `Quick review`: [`references/quick.md`](references/quick.md), then steps 6 and 7.
- `Draft a reply`: the decide or decline reply of comment-guidelines.md, then step 7.
- `Stop`: nothing more.

With `--quick` in the arguments, take the quick review without the question. If the
reviewer asks about the goal first, stay in step 2.

### 4. Write the notes file, then fan out

Follow pipeline.md §2 and §3. If you have Settled facts or Open leads, write the `notes:` file
that the plan names. Then launch every pass in one message from the `=== PROMPTS ===` block,
verbatim and with no `name` (delivery.md).

On a same-repo PR, the code pass reports no `reuse` or `maintainability` findings, and its
printed prompt says so. On a fork PR it keeps both, because the team judgment of fit comes
from the review. `--deep N` overrides the deep budget of the change pass. The blocks are
evidence for the report. Never post them.

### 5. Triage

Run the roll call. Then triage per pipeline.md §4 and §5, and severity.md. One filter decides
what reaches the PR:

**Keep** a finding only when it impacts correctness, performance, security or maintainability.
It must be discrete and actionable, and this PR must have introduced it. It must have provable
impact and be clearly not intentional. A finding that reverts a commit of this branch is
intentional by default (the `commits:` list). Post it as a `question (design)`, or drop it.

**Drop** style nits, unless they obscure meaning or break a quoted convention. Drop rigor
demands that the codebase does not follow, pre-existing bugs, generic observations, and
restatements of the code. Drop what you cannot confirm and what a green check answers. An
inaccurate comment is more harmful than a missed issue.

**Never post a finding that is already on the PR** (`already raised`, pipeline.md §5.2).
Post a contradiction as a `question` reply into its thread (`--reply <id>`). A `dismissed`
finding never posts. A `not fixed` finding posts as an `issue` reply into its thread.

**Redirect.** When a finding names a better location or mechanism with a precedent, and
the rest of the PR depends on that choice, set the verdict to `redirect`.

Rank first the A findings that reach released behavior or security.

**Revert check**, only when the plan says `fork: false`, the type is `fix`, `HEAD` is the plan
`head` and the tree is clean. Disable one part of the fix at a time. Run the tests of the
package after each change. Restore the file with `git checkout -- <path>` after each run. A
new test that still passes is a `question (tests)`. Two parts whose tests pass without each
other are a `scope` split. On a fork PR, a claim that needs a run stays a `question`.

### 6. Present findings

Follow [`references/present.md`](references/present.md): the chat template, the verdict rule
and the gate questions. **Never post without confirmation.**

### 7. Post (only after the user confirms)

- Findings: one review, per *Posting a review with post-review.sh* in comment-guidelines.md.
  `One summary review` adds `--body-only`. Post replies into threads with
  `post-comment.sh --reply`.
- A decide or decline reply: show the draft. Post it with `post-comment.sh --no-label`.

Reply with the link of each posted comment or review.
