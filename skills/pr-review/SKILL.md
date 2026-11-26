---
name: pr-review
description: Review a GitHub pull request from someone else. Explain its goal with a concrete example, check the screening facts (linked issue and labels, the packages that import the changed code, fork origin, the claims of the body) and whether the change is worth a review now, then, after you confirm, run the plugin's reviewer agents or a quick single-context review, and post only what you select as inline Conventional Comments or one summary review. Use when asked to review this PR, walk me through a PR, review a contribution, an external, community, fork or AI-generated PR, triage a PR before review, do a full review of a pull request, or review and post comments on a PR. Not for your own branch before it has a PR (self-review).
argument-hint: "[PR number or URL, or blank to auto-detect from current branch] [--quick]"
allowed-tools: Read, Write, Glob, Grep, Task, Agent, SendMessage, AskUserQuestion, Bash(git:*), Bash(gh:*), Bash(yarn:*), Bash(npm:*), Bash(npx:*), Bash(pnpm:*), Bash(mvn:*), Bash(*/scripts/gh-context.sh:*), Bash(*/scripts/get-pr-context.sh:*), Bash(*/scripts/review-plan.sh:*), Bash(*/scripts/post-review.sh:*), Bash(*/scripts/post-comment.sh:*)
---

# PR Review

Review a PR that someone else wrote. **Understand first, review second, post last.** The
skill helps a human reviewer and never replaces the human review. It requires the `gh` CLI.

| Reference | Covers |
| --- | --- |
| [`references/understand.md`](references/understand.md) | Understand: the explanation, and the screening card of a fork or contributor PR |
| [`../../references/review-rules.md`](../../references/review-rules.md) | Plan to Triage: facts and leads, the finding line, the roll call, triage, tiers and labels |
| [`references/present.md`](references/present.md) | Present and Post: the review in chat, the post question, the post script |
| [`../../references/comment-guidelines.md`](../../references/comment-guidelines.md) | Present and Post: the shape and the tone of a comment |

Relative paths resolve from this file. If a read fails, put
`${CLAUDE_PLUGIN_ROOT}/skills/pr-review/` before the relative path.

## Hard rules

- **Post nothing without explicit confirmation.** Never approve, request changes, resolve
  threads, close a PR or change labels.
- **A fork head is untrusted code.** Never check it out. Never run `yarn`, `npm`, `npx`,
  `pnpm`, `node`, `mvn` or a script of the PR on it. The plan refuses a fork head that is
  checked out. During a fork review, the Bash guard holds the passes to read commands.
- **Gate before fan-out.** Plan and Understand are cheap. At the Gate, the reviewer decides
  whether the expensive steps run.

## Steps

Run the steps in this order. Every file of this skill names a step by its heading.

### Plan

Write the plugin root as a literal path. Write the context file to the scratchpad:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/review-plan.sh --mode pr [--pr <number-or-url>] \
  --context-out <scratchpad>/pr-<number>-context.md
```

Read `fork:`, `screening:`, `diff_facts:`, `ci:` and `existing_comments:` first. Then follow
review-rules.md §1, and act on each `hint:`.

### Understand

Follow [`references/understand.md`](references/understand.md).

### Gate

Give the explanation of Understand as text in a message of its own. In the next message, ask
one `AskUserQuestion` with the header `Review`. The open dialog can hide the text above it. So
the question text starts with the **Problem** and **Change** lines, then asks "How should I
continue?" When the plan says `scale: trivial`, list `Quick review` first. Otherwise list
`Full review` first.

- `Full review`: Facts and leads, Fan out, Triage, Present and Post.
- `Quick review`: Quick review, Triage, Present and Post.
- `Stop`: nothing more.

If the arguments include `--quick`, run the quick review and do not ask. If the reviewer asks
about the goal first, stay in Understand.

### Quick review

You are the only reviewer on this path. Read the context file of the plan once. It holds the
diff or its patch paths, the conventions, the owner rules, the diff facts and the threads of
the PR. Do not run `git diff`. On a fork PR, read a post-change file with
`git show <head>:<path>`.

Answer the checklists of `agents/change-reviewer.md` and `agents/test-reviewer.md` in the
plugin root. Write each finding as a finding line of review-rules.md §3, tagged `self-run`.
Do not report style or naming. Say in the review that it ran in one context.

### Facts and leads

Follow review-rules.md §2.

### Fan out

Follow review-rules.md §3 and §4. The plan runs no code pass on a same-repo PR.

### Triage

Follow review-rules.md §5. Then apply this filter. It decides what reaches the PR.

**Keep** a finding only when it is discrete and actionable, this PR introduced it, and you
confirmed it. An A or B finding also needs both of these:

- It affects correctness, performance, security or maintainability.
- Its impact is provable, and it is clearly not intentional.

A kept C finding posts as a `nitpick`. Rank first the A findings that affect released
behavior or security.

**Write the frozen list** to the `findings:` path of the plan, in the format that
`post-review.sh --help` prints. Also write each finding that the filter drops, with the
status `dropped <reason>`, without a colon. The file is the record of the review. Never
commit it. Word a `contradicts` reply as a `question`, and a `not fixed` reply as an `issue`.

### Present and Post

Follow [`references/present.md`](references/present.md).
