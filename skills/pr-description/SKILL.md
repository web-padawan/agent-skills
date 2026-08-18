---
name: pr-description
description: Write or rewrite the description of a Vaadin pull request from the branch diff — fills the repo PR template as short, bullet-driven markdown with a "How to test" section. Use when asked to write a PR description, fill in the PR template, describe this branch for a PR, update or improve the PR body, or add a how-to-test section. Drafts in chat and only updates the PR after explicit confirmation. Not for reviewing a PR (guided-review, adversarial-review, pr-review) or for reviewing your own branch before opening it (self-review).
argument-hint: "[PR number or URL, or blank to use the current branch]"
---

# PR Description

Turns a branch diff into a PR description in the style the `vaadin/web-components` and
`vaadin/flow-components` repos actually use: a couple of issue links, a **bullet list of
what changed**, a type label, and concrete steps to verify it by hand.

The goal is a description a reviewer can read in under a minute. Prose is the exception,
not the default — see [references/STYLE.md](references/STYLE.md).

## Hard rules

- **Never update the PR without explicit confirmation.** Draft in chat first, always.
- **No `🤖 Generated with Claude Code` footer**, no AI attribution of any kind. It is
  absent from every PR this style is drawn from.
- **No placeholder text in the output.** Omit a section instead of shipping an empty one.
  The one exception is the `Before / After` image cells (Stage 3).
- **Drop the template's `## Checklist` block.** It is in `PULL_REQUEST_TEMPLATE.md` and in
  none of the merged PRs.

## Stage 1 — Gather

```bash
BASE=$(git rev-parse --abbrev-ref origin/HEAD 2>/dev/null | sed 's|origin/||' || echo main)
git log --oneline "origin/$BASE"..HEAD
git diff "origin/$BASE"...HEAD --stat
git diff "origin/$BASE"...HEAD
gh pr view --json number,title,body,url,headRefName   # existing PR, if any
cat PULL_REQUEST_TEMPLATE.md                          # repo root, not .github/
```

Collect the issue links from, in order: the existing PR body, commit trailers
(`Fixes #NNNN`), the branch name, and what the user said. Read the linked issue
(`gh issue view <n>`) when the diff alone does not explain the _why_.

If the change is not self-explanatory, read the surrounding source — a description built
from the diff alone tends to list files instead of behavior.

## Stage 2 — Classify

Pick exactly one type from the five values these repos use. Map the conventional-commit
prefix of the PR title, falling back to the commit subjects, then to the diff shape:

| Prefix     | Type of change  |
| ---------- | --------------- |
| `feat`     | Feature         |
| `fix`      | Bugfix          |
| `refactor` | Refactor        |
| `docs`     | Documentation   |
| `test`     | Tests           |
| `chore`    | Internal change |

Mixed branches take the type of the change a reviewer cares about most — a `fix` with
supporting test cleanup is still a Bugfix.

## Stage 3 — Draft

Build the body from [references/TEMPLATE.md](references/TEMPLATE.md) and apply the voice
rules in [references/STYLE.md](references/STYLE.md). Section order is fixed:

`## Description` → `## Type of change` → `## How to test` → `## Before / After`

`How to test` is omitted when there is nothing to click — a dependency bump, a
types-only change, a pure internal refactor. `Before / After` is only for changes with a
visual or recorded result; scaffold it with `<!-- paste screenshot -->` cells and say
plainly in chat that the images have to be attached by hand before the PR is publishable.

## Stage 4 — Deliver

Print the full draft in chat. Then ask with a single `AskUserQuestion` (header `Apply`):

- **Existing PR** — "Update the PR description?" → on yes, write the body to a file in the
  session scratchpad and run `gh pr edit <number> --body-file <that literal path>`.
  Always `--body-file`; backticks and `$` get mangled through `--body`. Write the path out
  literally — shell variables do not persist between tool calls.
- **No PR yet** — write the body file and print the ready-to-run
  `gh pr create --title "<title>" --body-file <path>`. Do not run it.

Never `gh pr create`, `gh pr merge`, or touch labels, reviewers or milestones.

## Agent guidelines

- One bullet per behavior change, not per file. Cap at ~10; more means the bullets are too
  granular or the PR is too big — say so rather than padding the list.
- Full URLs for cross-repo links (`https://github.com/vaadin/flow-components/issues/9842`),
  bare `#NNNN` only within the same repo.
- `Fixes <url>` for issues this closes; `Part of`, `Extracted from`, `Depends on`,
  `Related to` for everything else. These go first, above the bullets.
- Keep an existing body's issue links and any hand-written notes when rewriting; replace
  only what you can rebuild from the diff.
- Name real paths in `How to test` — `dev/<component>.html` in web-components, the
  `*-integration-tests/**/<Name>View.java` view in flow-components. Verify the file exists.
