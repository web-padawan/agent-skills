---
name: guided-review
description: Use when you want to understand and review a GitHub pull request as a reasoning companion rather than an automated reviewer. Phase 1 explains the PR's goal and purpose concisely with a concrete example, then gates on your confirmation before Phase 2 does a thorough code review that surfaces genuine issues, not nitpicks. Read-only — never posts anything to the PR; you post any feedback yourself. This is the default for "review this PR" / "walk me through this PR" requests; when the goal is to post comments, use pr-review or adversarial-review explicitly instead. Not for your own branch before it has a PR (self-review).
argument-hint: "[PR number, URL, or blank to auto-detect from current branch]"
allowed-tools: Bash(gh pr view:*), Bash(gh pr diff:*), Bash(gh pr checks:*), Bash(git diff:*), Bash(git log:*), Bash(git show:*), Bash(git merge-base:*), Bash(git fetch:*), Read, Grep, Glob
---

# Guided Review

A two-phase walkthrough for a PR that a reviewer asked you to review. **Understand first,
critique second**, and never on behalf of the reviewer. This skill augments human review. It
does not replace it.

## Hard rules

- **Never post anything to the PR.** No comments, reviews, replies, approvals, suggestions,
  thread resolutions, or label/status changes. Not with `gh pr comment`, not with
  `gh pr review`, not with `gh api`, not by any other path. The reviewer posts everything.
  Only read from the PR.
  - If the reviewer asks you to draft comment text, print it in the chat for the reviewer to
    copy. Do not send it.
- **Be concise.** Lead with substance. No filler, no line-by-line restatement of the diff, no
  walls of text. The goal is to save review time, not to produce an essay.
- **Gate between phases.** Do not start the code review until the reviewer confirms. See below.

## Phase 1 — Understand the goal and purpose

Goal: build a solid mental model of *what this PR is for and why*, fast.

1. Load the PR (read-only):
   - If the reviewer gave a number or URL, use it. Otherwise detect the PR from the current
     branch: `gh pr view`.
   - `gh pr view <id>` for title, description, author, target branch, linked issues.
   - `gh pr diff <id>` and/or `git diff <target>...<source> --stat` for the shape of the change.
   - Skim the linked issue and the description for the problem that motivates the PR, not only
     the "what".
2. Explain it back concisely:
   - **Problem**: the broken or missing behavior (1 to 2 sentences).
   - **Change**: what this PR does about it (1 to 2 sentences).
   - **How it works**: the mechanism, only as deep as the reviewer needs to grasp it.
   - **Simple example**: a concrete before/after. Use a sample input→output, a user-visible
     scenario, or a tiny code walkthrough. Make the abstract tangible. This part is mandatory,
     not optional.
   - **Scope**: the main files and areas touched, grouped by concern (not a full file list).
3. Keep it tight. Prefer short paragraphs or a few bullets to long prose. If the PR itself does
   not make a point clear, say so. Do not guess.

**Then stop and ask:** *"Ready to review the code changes thoroughly?"* Wait for the answer. Do
not proceed to Phase 2 until the reviewer says yes. If the reviewer first has questions about
the goal or purpose, stay in Phase 1. Answer the questions there.

## Phase 2 — Thorough code review

Start this phase only after the reviewer confirms.

**Before the review, load the repo conventions** and apply them. Use `CONVENTIONS.md` at the
repo root if it exists. Otherwise use the conventions section of `CLAUDE.md` / `AGENTS.md`.
Otherwise infer the dominant patterns of the touched packages.

Also read the existing discussion of the PR (`gh pr view <id> --json comments,reviews`). Do not
repeat points that others already made or that the author addressed.

Focus on **genuine issues that matter**. Rank the most serious first:

- **Correctness**: bugs, wrong logic, edge cases, null/undefined handling, race conditions,
  off-by-one, incorrect queries.
- **Regressions & safety**: behavior changes, security holes, missing error handling,
  performance cliffs, migration/data risks.
- **Coverage gaps**: untested branches or new behavior with no test.
- **Architecture fit**: does the PR follow established patterns? Does it add avoidable debt or
  scope creep? Apply the minimal-change principle: flag touched layers that are not
  load-bearing.

**Do not nitpick.** Skip style, naming preferences, formatting, and micro-optimizations. The
exception is a point that causes a real bug or that truly blocks comprehension. When a point is
minor but still worth a mention, label it explicitly as a nit. Keep it to one line, so that the
reviewer sees that it is not a blocker.

For each real issue, give **`file:line`, what is wrong, why it matters, and the concrete
failure scenario or fix.** Verify each claim against the actual code before you assert it
(Read/Grep the code around it). No speculative findings.

Close with a short, actionable verdict: are there blockers, or is the PR good to approve? The
reviewer continues from there and posts any feedback.
