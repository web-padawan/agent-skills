---
name: pr-description
description: Write or rewrite the description of a Vaadin pull request from the branch diff — fills the repo PR template as short, bullet-driven markdown with a "How to test" section. Use when asked to write a PR description, fill in the PR template, describe this branch for a PR, update or improve the PR body, or add a how-to-test section. Drafts in chat and only updates the PR after explicit confirmation. Not for reviewing a PR (guided-review, adversarial-review, pr-review) or for reviewing your own branch before opening it (self-review).
argument-hint: "[PR number or URL, or blank to use the current branch]"
---

# PR Description

This skill writes a PR description from a branch diff in the style of the
`vaadin/web-components` and `vaadin/flow-components` repos. That style has four parts: a few
issue links, a **bullet list of what changed**, a type label, and manual steps to verify the
change.

The goal is a description that a reviewer can read in under a minute. Prose is the
exception, not the default. See [references/STYLE.md](references/STYLE.md).

## Hard rules

- **Never update the PR without explicit confirmation.** Draft in chat first, always.
- **No `🤖 Generated with Claude Code` footer**, no AI attribution of any kind. The PRs
  that define this style do not have it.
- **No placeholder text in the output.** Omit a section instead of an empty section. The
  one exception is the `Before / After` image cells (Stage 3).
- **Drop the `## Checklist` block of the template.** The block is in
  `PULL_REQUEST_TEMPLATE.md` and in none of the merged PRs.

## Stage 1 — Gather

```bash
BASE=$(git rev-parse --abbrev-ref origin/HEAD 2>/dev/null | sed 's|origin/||' || echo main)
git log --oneline "origin/$BASE"..HEAD
git diff "origin/$BASE"...HEAD --stat
git diff "origin/$BASE"...HEAD
gh pr view --json number,title,body,url,headRefName   # existing PR, if any
cat PULL_REQUEST_TEMPLATE.md                          # repo root, not .github/
```

Collect the issue links in this order: existing PR body, commit trailers (`Fixes #NNNN`),
branch name, and what the user said. If the diff alone does not explain the _why_, read
the linked issue (`gh issue view <n>`).

If the change is not self-explanatory, read the surrounding source. A description built
from the diff alone tends to list files instead of behavior.

## Stage 2 — Classify

Pick exactly one type from the five values that these repos use. Map the
conventional-commit prefix of the PR title with this table. If the title has no prefix,
use the commit subjects. If the subjects have no prefix, use the diff shape:

| Prefix     | Type of change  |
| ---------- | --------------- |
| `feat`     | Feature         |
| `fix`      | Bugfix          |
| `refactor` | Refactor        |
| `docs`     | Documentation   |
| `test`     | Tests           |
| `chore`    | Internal change |

For a mixed branch, use the type of the change that a reviewer cares about most. A `fix`
with supporting test cleanup is still a Bugfix.

## Stage 3 — Draft

Build the body from [references/TEMPLATE.md](references/TEMPLATE.md). Apply the voice
rules in [references/STYLE.md](references/STYLE.md). The section order does not change:

`## Description` → `## Type of change` → `## How to test` → `## Before / After`

If there is nothing to click, omit `How to test`. Dependency bumps, types-only changes,
and pure internal refactors are examples. Use `Before / After` only for changes with a
visual or recorded result. Scaffold it with `<!-- paste screenshot -->` cells. Say plainly
in chat that the user must attach the images by hand before the PR is publishable.

## Stage 4 — Deliver

Print the full draft in chat. Then ask with a single `AskUserQuestion` (header `Apply`):

- **Existing PR**: ask "Update the PR description?". On yes, write the body to a file in
  the session scratchpad. Then run `gh pr edit <number> --body-file <that literal path>`.
  Always use `--body-file`, because `--body` mangles backticks and `$`. Write the literal
  path, because shell variables do not persist between tool calls.
- **No PR yet**: write the body file. Print the ready-to-run
  `gh pr create --title "<title>" --body-file <path>`. Do not run it.

Never run `gh pr create` or `gh pr merge`. Never touch labels, reviewers or milestones.

## Agent guidelines

- Write one bullet per behavior change, not per file. Cap the list at about 10 bullets.
  More than that means that the bullets are too granular or the PR is too big. Do not pad
  the list. Say so in chat instead.
- Use full URLs for cross-repo links
  (`https://github.com/vaadin/flow-components/issues/9842`). Use bare `#NNNN` only within
  the same repo.
- Use `Fixes <url>` for issues that this PR closes. Use `Part of`, `Extracted from`,
  `Depends on`, or `Related to` for everything else. Put these links first, above the
  bullets.
- When you rewrite an existing body, keep its issue links and any hand-written notes.
  Replace only what you can rebuild from the diff.
- Name real paths in `How to test`: `dev/<component>.html` in web-components, the
  `*-integration-tests/**/<Name>View.java` view in flow-components. Verify that the file
  exists.
