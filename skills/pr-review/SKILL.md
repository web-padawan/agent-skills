---
name: pr-review
description: Review a GitHub pull request from someone else. Explain its goal with a concrete example, check the screening facts (linked issue and labels, the packages that import the changed code, fork origin, the claims of the body) and whether the change is worth a review now, then, after you confirm, run the plugin's reviewer agents or a quick single-context review, and post only what you select as inline Conventional Comments, one summary review, or a drafted reply. Use when asked to review this PR, walk me through a PR, review a contribution, an external, community, fork or AI-generated PR, triage a PR before review, do a full review of a pull request, or review and post comments on a PR. Not for your own branch before it has a PR (self-review).
argument-hint: "[PR number or URL, or blank to auto-detect from current branch] [--deep N] [--quick]"
allowed-tools: Read, Write, Edit, Glob, Grep, Task, Agent, SendMessage, AskUserQuestion, Bash(git:*), Bash(gh:*), Bash(yarn:*), Bash(npm:*), Bash(npx:*), Bash(pnpm:*), Bash(*/scripts/gh-context.sh:*), Bash(*/scripts/get-pr-context.sh:*), Bash(*/scripts/review-plan.sh:*), Bash(*/scripts/pr-refresh.sh:*), Bash(*/scripts/post-review.sh:*), Bash(*/scripts/post-comment.sh:*)
---

# PR Review

Review a PR that someone else wrote. **Understand first, review second, post last.** The
skill helps a human reviewer and never replaces the human review. It requires the `gh` CLI.

Parallel read-only reviewer agents, the passes, run the full review. They read a context file
that a script writes.

| Reference | Covers |
| --- | --- |
| [`references/understand.md`](references/understand.md) | Understand and Gate: the explanation, the screening card and verdicts, the claims of the body |
| [`references/quick.md`](references/quick.md) | Gate: the quick review, also the fallback |
| [`../../references/pipeline.md`](../../references/pipeline.md) | Plan, Fan out and Triage: the plan, the context and notes files, the fan-out, the roll call, triage |
| [`../../references/severity.md`](../../references/severity.md) | Triage: A / B / C, tiers by change type, what CI settles, the rendering table |
| [`../../references/delivery.md`](../../references/delivery.md) | Fan out and Triage: launch rules, the delivery clause, the roll call, the escalation ladder |
| [`../../references/comment-guidelines.md`](../../references/comment-guidelines.md) | Present and Post: comment tone, replies by verdict, posting |
| [`references/present.md`](references/present.md) | Present: the chat template, the result rule, the post gate |

Relative paths resolve from this file. If a read fails, put
`${CLAUDE_PLUGIN_ROOT}/skills/pr-review/` before the relative path.

## Hard rules

- **Post nothing without explicit confirmation.** Never approve, request changes, resolve
  threads, close a PR or change labels.
- **A fork head is untrusted code.** Never check it out. Never run `yarn`, `npm`, `npx`,
  `pnpm`, `node` or a script of the PR on it. The plan refuses a fork head that is checked
  out. While a fork review runs, the Bash guard of the plugin lets the passes run only read
  commands.
- **Gate before fan-out.** Plan and Understand are cheap. At the Gate, the reviewer decides
  whether the expensive steps run.

## Steps

Run the steps in this order. Every file of this skill names a step by its heading.

### Plan

Run the plan script once. Write the plugin root as a literal path. Write the context file to
the scratchpad:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/review-plan.sh --mode pr [--pr <number-or-url>] [--deep N] \
  --context-out <scratchpad>/pr-<number>-context.md
```

Read `fork:`, `screening:`, `diff_facts:`, `ci:`, `existing_comments:` and `workflow:` first. Then read the
rest of the plan per pipeline.md §1, and act on every `hint:`.

### Understand

Follow [`references/understand.md`](references/understand.md).

### Gate

Before you ask, run `${CLAUDE_PLUGIN_ROOT}/scripts/pr-refresh.sh --at gate --context <context file>`.
Act on each `action:` line.

Ask one `AskUserQuestion` with the header `Review`: "How should I continue?" List first the
option that the verdict suggests (*Screening verdicts* in [`references/understand.md`](references/understand.md)):

- `Full review`: Fan out, Triage, Present and Post.
- `Quick review`: [`references/quick.md`](references/quick.md).
- `Draft a reply`: the reply of *Replies by verdict* in comment-guidelines.md, then Post.
- `Stop`: nothing more.

If the arguments include `--quick`, run the quick review and do not ask. If the reviewer asks
about the goal first, stay in Understand.

### Fan out

Write the notes file first. Follow pipeline.md §2 and §3, and the launch rules of
delivery.md. The deep blocks of the change pass are evidence for Triage. Never post them.

### Triage

Run `pr-refresh.sh --at triage`, then the roll call. Act on each `action:` line. Then triage
per pipeline.md §4 and §5, and severity.md. One filter decides what reaches the PR.

**Keep** a finding only when it is discrete and actionable, this PR introduced it, and you
confirmed it. An A or B finding also needs both of these:

- It affects correctness, performance, security or maintainability.
- Its impact is provable, and it is clearly not intentional.

A kept C finding posts as a `nitpick`.

A finding that reverts a commit of this branch is intentional by default (the `commits:` list).
Post it as a `question (design)`, or drop it.

**Drop** these findings. An inaccurate comment is more harmful than a missed issue.

- Rigor demands that the codebase does not follow.
- Pre-existing bugs, generic observations and restatements of the code.

**Write the frozen list** (pipeline.md §5.7) to `<scratchpad>/pr-<number>-findings.json`, in
the format that `post-review.sh --help` prints: `file`, `line`, `message`, `status`, `dup`
and `summary_only`. Also write each finding that the filter drops, with the status
`dropped <reason>`. The script posts from that file, and the file is the record of the review.
Never commit it. It never opens a new thread for a
finding that is already on the PR (pipeline.md §5.2). Word a `contradicts` reply as a
`question`, and a `not fixed` reply as an `issue`.

**Redirect**: a finding can name a better location or mechanism with a precedent. When the rest
of the PR depends on that choice, set the verdict to `redirect`.

Rank first the A findings that affect released behavior or security.

### Present

Follow [`references/present.md`](references/present.md).

### Post

Post as comment-guidelines.md describes, from the findings file of Triage. `One summary
review` adds `--body-only`. `Only blocking issues` adds `--blocking-only`. Give the link of
each posted comment or review.
