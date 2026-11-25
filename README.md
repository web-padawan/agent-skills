# agent-skills

Private Claude Code plugin with personal skills. The repository is both the plugin and a
single-plugin marketplace. You install it from a local path. Nothing is published.

## Skills

| Skill | Use it for |
| --- | --- |
| `pr-review` | A PR from someone else. Explains it, checks the screening facts, reviews it after you confirm with the agent passes or in one context, then posts only what you select. |
| `self-review` | Your own branch before you open or update a PR. Three agent passes, A / B / C findings, a `FINDINGS.md` report. Never edits code. |
| `comment-cleanup` | Deletes and shortens comments in a diff, a file or a package. Edits comment lines only. |
| `screenshot-diff` | Classifies visual test screenshot diffs. Never updates a baseline. |
| `work-summary` | A manager summary of your merged PRs for a period. |
| `issue-draft` | A short issue draft in the issue form of the target repository. Writes a local file and posts nothing. |
| `codebase-onboarding` | An onboarding guide and a starter `CLAUDE.md` for an unfamiliar Node.js codebase. Never changes an existing `CLAUDE.md`. |
| `authoring-skills` | Conventions to create or improve a skill in this plugin. |

Each skill that writes to GitHub asks for confirmation first. Review comments start with
`:robot: AI-generated`.

## Install

```bash
claude plugin marketplace add /Users/serhii/vaadin/agent-skills
claude plugin install agent-skills@local
```

Restart the session so that the skills load.

## Use

```
/agent-skills:pr-review 9042                    # walkthrough, screening, review, optional posting
/agent-skills:pr-review 9042 --quick            # the same, with a single-context review
/agent-skills:self-review                       # current branch, type detected
/agent-skills:self-review --fix --no-coverage   # force type, skip the coverage check
/agent-skills:self-review --rounds 3            # up to 3 rounds, stops when one adds no new A or B
/agent-skills:self-review --fresh               # ignore the findings file of the last run
/agent-skills:comment-cleanup --commit HEAD
/agent-skills:screenshot-diff packages/button
/agent-skills:work-summary menu-bar --since 2026-08-01 --until 2026-09-30
/agent-skills:issue-draft bug                   # one issue draft from the findings of the session
/agent-skills:issue-draft --repo owner/name 123 # a new body for an existing issue, as a draft
/agent-skills:codebase-onboarding               # guide and starter CLAUDE.md of a Node.js repo
```

## Review pipeline

`self-review` and `pr-review` share one pipeline:

- `scripts/review-plan.sh` resolves the profile in `scripts/lib/policy.sh` into a plan.
  It also writes the context file that every pass reads.
- The three agents in `agents/` run in parallel: change, code and tests.
- `references/pipeline.md` describes the plan, the fan-out, the roll call and the triage.
- `references/severity.md` defines the A / B / C tiers and the Conventional Comments labels.

`docs/contracts.md` lists the plan keys and the contracts of the extension points: fact
packs, owner directories, the findings file and the prompt block. The rest of `docs/` holds the
design history. No skill loads it.

The review core works on a repository of any owner. It supports JavaScript and TypeScript
projects with a root `package.json`, and Java projects with a root `pom.xml`. It reads these
docs of the repository as its conventions, in this order: `.github/review-instructions.md`,
`.github/copilot-instructions.md`, `CONVENTIONS.md`, `CLAUDE.md`, `AGENTS.md`,
`CONTRIBUTING.md` and `CODING_STANDARDS.md`. The context file quotes them while their total
stays at 400 lines or less. Rules, facts and screening labels for the repositories of one
owner live in an owner directory (see Config). `owners/vaadin/` holds those of Vaadin.

Other skills share files with the review pipeline. `comment-cleanup` reads
`references/comments.md`, and `work-summary` calls `gh-context.sh`.

## Scripts

Run each script from inside the target repository. Each one prints its usage with `--help`.
The exit codes are 0 for success, 1 for failed work, and 2 for a usage or guard error.

| Script | Does |
| --- | --- |
| `gh-context.sh` | One issue or PR as markdown, with comments, reviews and threads |
| `post-comment.sh` | One Conventional Comment on a PR, inline or general, or a reply |
| `post-review.sh` | All selected findings as one PR review: line, then file, then body anchors |
| `review-plan.sh` | The review plan and the context file of the pipeline |
| `pr-screen.sh` | The screening facts of a PR: author, linked issue, labels, verdict hint |
| `diff-facts.sh` | The git-only facts of a diff: diff noise, new test files, and the facts of each fact pack |
| `owners/vaadin/facts/web-components.sh` | Fact pack of a web component monorepo: reach, Flow counterpart, CSS unit assertions, shadow DOM reads |
| `owners/vaadin/facts/flow-components.sh` | Fact pack of a Flow repository: the web component declaration of each synced property and called method, also when it is newer than the pinned version |
| `get-pr-context.sh` | PR metadata, anchor SHAs, CI state, related PRs and diffs for `review-plan.sh` |
| `related-prs.sh` | The stack parent, the children and other open PRs of the author on the same files, with their threads |
| `dev-server.sh` | Start, check, restart or stop `web-dev-server` on one port |
| `test-summary.sh` | One line per test suite, with the names of failing tests |
| `probe.cjs` | A probe module against a dev page, per theme and direction |
| `probe-compare.cjs` | A diff of two probe result files |
| `ab.sh` | One command on the current tree and on paths from another ref, then a diff |
| `mutant.sh` | The tests against one mutant, then the restore and a clean tree check |
| `fixup-into.sh` | Folds changes into an earlier branch commit |
| `float-to-tip.sh` | Moves one branch commit to the tip |
| `visual-diffstat.cjs` | Pixel metrics and a contact sheet for failed screenshots |
| `smoke.sh` | Checks the scripts that rewrite a tree, the diff and screening facts and the Bash guard |

## Config

An owner directory holds what applies only to the repositories of one GitHub owner:

- `facts/*.sh`: fact packs that `diff-facts.sh` runs, per the provider contract in `docs/contracts.md`
- `screening.json`: the screening labels, the team allowlist and the advisory CI checks. `pr-screen.sh --help` lists the screening keys. `get-pr-context.sh --help` describes `advisory_checks`
- `rules.md`: review rules. The context file quotes them for the passes, and triage reads them

The owner is the owner of the `upstream` remote, else of `origin`. The lookup reads
`$REVIEW_SKILLS_CONFIG_DIR/<owner>/` first. The default of that variable is
`~/.config/agent-skills`. Then it reads `owners/<owner>/` of this plugin. Without an owner
directory, only the generic facts and screening rules apply.

To add an owner, create `~/.config/agent-skills/<owner>/` with any of the three parts. The
plan prints `fact_packs:` and `owner_rules:`, so a review shows what it loaded. A directory
in the config dir replaces the directory of the same owner in this plugin.

## Hooks

`hooks/hooks.json` registers `scripts/hooks/bash-guard.py` before every Bash call. The guard
acts only on the three reviewer agents. It denies commands that write. While a fork review
runs, it allows read commands only. `review-plan.sh` writes the fork marker for a fork PR.
The marker expires after 3 hours, and a review of a same-repo PR removes it.

`hooks/hooks.json` also registers `scripts/hooks/notes-guard.py` before every Agent call. The
guard acts only on a prompt of the plan. It denies the launch of a pass while the notes file
of that prompt does not exist. A pass that starts earlier reviews without the Settled facts.

`scripts/hooks/question-guard.py` runs before every AskUserQuestion call. It denies the
`Review` question of pr-review without the Problem and Change lines, and the `Post` question
without the findings that can post. The open dialog can cover the text above it.

## Update a skill

The plugin runs from a cached copy of one commit. Commit the change, run
`claude plugin update agent-skills@local`, and start a new session. Create a new skill with
`authoring-skills`.

## Dependencies

- The `gh` CLI, authenticated, for every skill that reads a PR or an issue.
- No owner by default. The owner directory of the repository under review adds its rules.
