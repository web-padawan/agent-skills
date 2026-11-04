---
name: pr-review
description: Review a GitHub pull request from someone else. Explain its goal with a concrete example, check the screening facts (linked issue and labels, the packages that import the changed code, fork origin, the claims of the body) and whether the change is worth a review now, then, after you confirm, run the plugin's reviewer agents or a quick single-context review, and post only what you select as inline Conventional Comments, one summary review, or a drafted reply. Use when asked to review this PR, walk me through a PR, review a contribution, an external, community, fork or AI-generated PR, triage a PR before review, do a full review of a pull request, or review and post comments on a PR. Not for your own branch before it has a PR (self-review).
argument-hint: "[PR number or URL, or blank to auto-detect from current branch] [--deep N] [--quick]"
allowed-tools: Read, Write, Edit, Glob, Grep, Task, Agent, SendMessage, AskUserQuestion, Bash(git:*), Bash(gh:*), Bash(yarn:*), Bash(npm:*), Bash(npx:*), Bash(pnpm:*), Bash(*/scripts/gh-context.sh:*), Bash(*/scripts/get-pr-context.sh:*), Bash(*/scripts/review-plan.sh:*), Bash(*/scripts/post-review.sh:*), Bash(*/scripts/post-comment.sh:*)
---

# PR Review

Review a PR that someone else wrote. **Understand first, review second, post last.** The
skill helps a human reviewer and never replaces the human review. It requires the `gh` CLI.

Parallel read-only reviewer agents, the passes, run the full review. They read a context file
that a script writes. You read the plan, not the diff. `yarn`, `npm`, `npx` and `pnpm` run
only in the revert check of a same-repo PR (step 5).

| Reference | Covers |
| --- | --- |
| [`references/understand.md`](references/understand.md) | Step 2: the explanation and the screening card |
| [`references/screening.md`](references/screening.md) | Steps 2 and 3: the verdicts, the hint table, the claims of the body |
| [`references/quick.md`](references/quick.md) | Step 3: the quick review, also the fallback |
| [`../../references/pipeline.md`](../../references/pipeline.md) | Steps 1, 4 and 5: the plan, the context and notes files, the fan-out, the roll call, triage |
| [`../../references/severity.md`](../../references/severity.md) | Step 5: A / B / C, tiers by change type, the rendering table |
| [`../../references/delivery.md`](../../references/delivery.md) | Steps 4 and 5: launch rules, the delivery clause, the roll call, the escalation ladder |
| [`../../references/comment-guidelines.md`](../../references/comment-guidelines.md) | Steps 6 and 7: comment tone, replies by verdict, posting. Read it before step 6 |
| [`references/present.md`](references/present.md) | Step 6: the chat template, the result rule, the post gate |

Relative paths resolve from this file. If a read fails, put
`${CLAUDE_PLUGIN_ROOT}/skills/pr-review/` before the relative path.

## Hard rules

- **Post nothing without explicit confirmation.** Never approve, request changes, resolve
  threads, close a PR or change labels.
- **A fork head is untrusted code.** Never check it out. Never run `yarn`, `npm`, `npx`,
  `pnpm`, `node` or a script of the PR on it. The plan refuses a fork head that is checked
  out. While a fork review runs, the Bash guard of the plugin lets the passes run only read
  commands.
- **Gate before fan-out.** Steps 1 and 2 are cheap. At step 3, the reviewer decides whether
  the expensive steps run.

## Steps

### 1. Plan

Run the plan script once. Write the plugin root as a literal path. Write the context file to
the scratchpad:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/review-plan.sh --mode pr [--pr <number-or-url>] [--deep N] \
  --context-out <scratchpad>/pr-<number>-context.md
```

Read `fork:`, `screening:`, `ci:` and `existing_comments:` first. Then read the rest of the plan
and act on every `hint:`. Record `base` and `head` as literals.

- A red check is an A finding on its own.
- A green check answers the findings of its class.
- If a `hint:` names a review bot, the bot has probably posted the easy findings.

### 2. Understand

Follow [`references/understand.md`](references/understand.md): problem, change, mechanism,
example and scope. On a fork PR, or on a PR from an author outside the team, add the
screening card.

### 3. Gate

Ask one `AskUserQuestion` with the header `Review`: "How should I continue?" List first the
option that the verdict suggests (the verdict table in [`references/screening.md`](references/screening.md)):

- `Full review`: steps 4 to 7.
- `Quick review`: [`references/quick.md`](references/quick.md), then steps 6 and 7.
- `Draft a reply`: the decide or decline reply (*Replies by verdict* in comment-guidelines.md),
  then step 7.
- `Stop`: nothing more.

If the arguments include `--quick`, run the quick review and do not ask. If the reviewer asks
about the goal first, stay in step 2.

### 4. Write the notes file, then fan out

Follow pipeline.md §2 and §3. If you have Settled facts or Open leads, write them to the
`notes:` file that the plan names. Then launch every pass in one message. Copy each prompt
from the `=== PROMPTS ===` block verbatim, and give no `name` (delivery.md).

On a same-repo PR, the code pass reports no `reuse` or `maintainability` findings. Its printed
prompt says so. On a fork PR, the code pass keeps both. The author is outside the team, so the
review must judge the fit. `--deep N` overrides the deep budget of the change pass. The deep
blocks of the change pass are evidence for the report. Never post them.

### 5. Triage

Run the roll call. Then triage per pipeline.md §4 and §5, and severity.md. One filter decides
what reaches the PR.

**Keep** a finding only when all of these are true:

- It affects correctness, performance, security or maintainability.
- It is discrete and actionable, and this PR introduced it.
- Its impact is provable, and it is clearly not intentional.

A finding that reverts a commit of this branch is intentional by default (the `commits:` list).
Post it as a `question (design)`, or drop it.

**Drop** these findings. An inaccurate comment is more harmful than a missed issue.

- Style nits, unless they obscure meaning or break a quoted convention.
- Rigor demands that the codebase does not follow.
- Pre-existing bugs, generic observations and restatements of the code.
- What you cannot confirm, and what a green check answers.

**Never post a finding that is already on the PR** (`already raised`, pipeline.md §5.2):

- A finding that contradicts its thread posts as a `question` reply into the thread (`--reply <id>`).
- A `dismissed` finding never posts.
- A `not fixed` finding posts as an `issue` reply into its thread.

**Redirect**: a finding can name a better location or mechanism with a precedent. When the rest
of the PR depends on that choice, set the verdict to `redirect`.

Rank first the A findings that affect released behavior or security.

**Revert check**: run it only when the plan says `fork: false`, the type is `fix`, `HEAD` is
the plan `head`, and the tree is clean. Disable one part of the fix at a time. After each
change, run the tests of the package. Then restore the file with `git checkout -- <path>`.

- A new test that still passes is a `question (tests)`.
- When the tests of two parts pass without each other, the parts are a `scope` split.
- On a fork PR, the check does not run, so a claim that needs a run stays a `question`.

### 6. Present findings

Follow [`references/present.md`](references/present.md): the chat template, the result rule
and the gate questions. **Never post without confirmation.**

### 7. Post (only after the reviewer confirms)

- Findings: post one review, as *Posting a review with post-review.sh* in comment-guidelines.md
  describes. `One summary review` adds `--body-only`. Post replies into threads with
  `post-comment.sh --reply`.
- A decide or decline reply: show the draft. Post it with `post-comment.sh --no-label`.

Give the link of each posted comment or review.
