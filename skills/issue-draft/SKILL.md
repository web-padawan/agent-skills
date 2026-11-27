---
name: issue-draft
description: Draft a GitHub issue (a bug report, a feature request, a refactor or a follow-up) in the issue form of the target repository, short and INVEST-shaped (one independent change, a motivation, a testable outcome). Use when asked to draft, write, file, report, open or create an issue, turn the findings of a session, a branch or a review into issues, split an issue into smaller ones, or draft a new body, new relations or new labels for an existing issue. Reads the issue form, the labels and the title convention of the repository. Writes a local draft file, prints it and posts nothing. Not for a comment on an issue, not for a pull request description, not for a review of a PR (pr-review), and not for a work report (work-summary).
argument-hint: "[bug|feature] [--repo owner/name] [issue number to update]"
allowed-tools: Read, Write, Edit, Glob, Grep, AskUserQuestion, Bash(git rev-parse:*), Bash(git show:*), Bash(git log:*), Bash(git ls-remote:*), Bash(gh repo view:*), Bash(gh issue view:*), Bash(gh issue list:*), Bash(gh search issues:*), Bash(gh label list:*), Bash(mkdir:*), Bash(diff:*), Bash(*/scripts/prose-check.sh:*)
---

# Issue Draft

This skill writes one GitHub issue draft for each independent change. It reads the issue form, the
labels and the title convention of the target repository. It assumes an authenticated `gh`.

The agent writes each draft to a local file and prints it. The agent never creates or edits an
issue. The user posts the draft. The tool list allows read commands only.

## Gotchas

- **A permalink must pin a full SHA.** A link to a branch points to other lines after the next merge.
  Read the lines at the SHA before you cite them.
- **A link to a local branch gives a 404.** A prototype branch must be on the remote before the user posts.
- **Find the existing pattern first.** Search how the sibling modules solve the same problem before
  you propose a solution.
- **One change, one issue.** A side fix that can merge alone gets its own issue. Link the two with `Related to`.
- **The agent cannot attach media.** If a video or a screenshot helps, tell the user to attach it.

## Stage 1 — Resolve the target

- **Repository**: the `--repo` argument. Else, run `gh repo view --json nameWithOwner --jq .nameWithOwner`.
- **Type**: `bug` or `feature`. A refactor and a follow-up use `feature`.
- **Scope**: one change that one PR can deliver. If the input holds more changes, list one issue per change.
  Ask which issues to draft.
- **Update**: if the user names an existing issue, run `gh issue view <n> --repo <owner/name> --json title,body,labels`.
  Keep its headings.

Ask only for facts that the session and the code cannot give.

## Stage 2 — Read the conventions

- **Form**: read the file in `.github/ISSUE_TEMPLATE/` of the checkout that fits the type.
  If the target repository has no checkout, use the default headings and report that.
- **Labels**: run `gh label list --repo <owner/name> --limit 200`. Use only labels of that list.
  Add the labels that the form sets in its `labels` key. `gh issue create` does not add them.
- **Titles**: run `gh issue list --repo <owner/name> --limit 20 --json title,labels`.
  Copy the title convention, for example a `[package]` prefix.

Take the headings from the first source in this table that exists:

| Source | Headings |
| --- | --- |
| A YAML form | The `label` of each field as `### <label>`, in form order. Skip `markdown` blocks. Fill each `required` field. |
| A markdown template | The headings of the template, in the same order. |
| Default, `bug` | Description, Expected outcome, Steps to reproduce, Environment |
| Default, `feature` | Motivation, Proposed solution, Alternatives considered |

## Stage 3 — Collect the evidence

- **Code**: get the SHA of the default branch with `git rev-parse origin/HEAD`.
  Read each cited range at that SHA with `git show <sha>:<path>`.
- **Duplicates**: run `gh search issues --repo <owner/name> "<keywords>"`. Link a related issue. Stop if a duplicate exists.
- **History**: run `git log -S "<code>"` to find the PR that added or changed the code.
- **Results**: copy the numbers, the cases and the screenshots of the session. Record what you did not test.

## Stage 4 — Write

- **Standard**: read [`../../references/writing.md`](../../references/writing.md) before you write.
  If that read fails, use `${CLAUDE_PLUGIN_ROOT}/references/writing.md`.
- **Relations**: put them on the first lines of the first section, one per line, without a bullet.
  Use `Part of`, `Depends on`, `Follow-up to`, `Related to` or `Requested in`.
  Put the problem or the goal in the first sentence after them.
- **Title**: for a bug, state the symptom. For a feature or a refactor, start with a verb.
  Put an identifier in backticks. Use 12 words or less. Do not end with a period.
- **Body**: keep it under 250 words of prose. Code blocks and links do not count.
  Omit an optional section that has no content.
- **Extra sections**: `Note`, `Out of scope` and `Open questions` can follow the form fields.
- **Permalink**: put it on its own line, so that GitHub shows the code.
- **Voice**: write facts as bullets. Name the module, the property and the file.
  In a bug, give the cause a `**Cause**:` label. Copy numbers from a test run or a measurement.

Then check the draft against each letter of INVEST:

| Letter | The draft passes when |
| --- | --- |
| Independent | It covers one change that can merge alone. An order between issues is a `Depends on` line. |
| Negotiable | It proposes and does not dictate. Choices go to Open questions. The release choice goes to Note. |
| Valuable | It names who has the problem: users, developers or maintainers. |
| Estimable | It names the files, the cause, permalinks and a prototype branch if one exists. |
| Small | The body has 250 words of prose or less. Above 400 words, cut the cause detail or split the issue. |
| Testable | The expected outcome or the requirements are statements that a test or a reviewer can check. |

## Stage 5 — Check

Run `mkdir -p /tmp/issue-drafts`. Write the body to `/tmp/issue-drafts/<repo>-<slug>.md`. Then check each fact:

- **Headings**: they match the source of Stage 2, in the same order. Each `required` field has content.
- **Permalinks**: each one pins a SHA of 40 characters. The line range exists in the file at that SHA.
- **Branch links**: `git ls-remote --heads origin <branch>` prints the branch. If not, record the push as an open fact.
- **References**: run `gh issue view <n> --repo <owner/name> --json title,state` for each issue or PR.
  Check that the relation word fits the title.
- **Labels**: each label is in the list of Stage 2.
- **Prose**: run `${CLAUDE_PLUGIN_ROOT}/scripts/prose-check.sh <file>`. Change the text at each `ban` hit.
  Keep a `flag` hit only when the word adds a fact. Run the check again until it exits 0.

## Stage 6 — Deliver

1. Print the repository, the title, the labels and the body in chat. Use a four-backtick `markdown` fence for the body.
2. For an update, also print the diff between the live body and the draft.
3. Print the path of the draft file.
4. List the open facts: a branch to push, a video to attach, a release label to choose.
5. Print the command that posts the draft, for the user to run:

   ```bash
   gh issue create --repo <owner/name> --title "<title>" --label "<label>" --body-file <file>
   ```

   For an update, print `gh issue edit <n> --repo <owner/name> --body-file <file>` instead.

## Agent guidelines

1. Never create, edit or comment on an issue. Never push a branch. The user does both.
2. Each claim about code traces to a permalink, a command output or a test run of this session.
3. Use a bare `#N` in the same repository and a full URL for another repository.
4. Use the headings of one source. Do not mix form labels with other headings.
5. Do not invent a version, a browser or an OS. Use the facts of the session, or ask.
6. Do not write an AI attribution line.
