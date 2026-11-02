# agent-skills

Private Claude Code plugin with personal skills. The repository is both the plugin and a
single-plugin marketplace. You install it from a local path. Nothing is published.

## Skills

| Skill | Use it for |
| --- | --- |
| `guided-review` | A PR from someone else. Explains the PR, reviews it after you confirm, then posts only the findings you select. |
| `self-review` | Your own branch before you open or update a PR. Three agent passes, A / B / C findings, a `FINDINGS.md` report. Never edits code. |
| `pr-review` | A full agent pass over a PR, then inline Conventional Comments after you confirm. |
| `refactor-component` | A structural refactor of web component sources without a behavior change. |
| `comment-cleanup` | Deletes and shortens comments in a diff, a file or a package. Edits comment lines only. |
| `screenshot-diff` | Classifies visual test screenshot diffs. Never updates a baseline. |
| `work-summary` | A manager summary of your merged PRs for a period. |
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
/agent-skills:guided-review 9042                # walkthrough, review, optional posting
/agent-skills:self-review                       # current branch, type detected
/agent-skills:self-review --fix --no-coverage   # force type, skip the coverage check
/agent-skills:self-review --rounds 3            # up to 3 rounds, stops when one adds no new A or B
/agent-skills:self-review --fresh               # ignore the findings file of the last run
/agent-skills:pr-review 9042 --deep 2           # agent pass, inline comments after you confirm
/agent-skills:refactor-component packages/<name>
/agent-skills:comment-cleanup --commit HEAD
/agent-skills:screenshot-diff packages/button
/agent-skills:work-summary menu-bar --since 2026-08-01 --until 2026-09-30
```

## Review pipeline

`self-review` and `pr-review` share one pipeline:

- `scripts/review-plan.sh` resolves the profile in `references/profiles.md` into a plan.
  It also writes the context file that every pass reads.
- The three agents in `agents/` run in parallel: change, code and tests.
- `references/pipeline.md` describes the plan, the fan-out, the roll call and the triage.
- `references/severity.md` defines the A / B / C tiers and the Conventional Comments labels.

`docs/` holds the design history. No skill loads it.

## Scripts

Run each script from inside the target repository. Each one prints its usage with `--help`.
The exit codes are 0 for success, 1 for failed work, and 2 for a usage or guard error.

| Script | Does |
| --- | --- |
| `gh-context.sh` | One issue or PR as markdown, with comments, reviews and threads |
| `post-comment.sh` | One Conventional Comment on a PR, inline or general, or a reply |
| `post-review.sh` | All selected findings as one PR review: line, then file, then body anchors |
| `review-plan.sh` | The review plan and the context file of the pipeline |
| `get-pr-context.sh` | PR metadata, anchor SHAs, CI state and diffs for `review-plan.sh` |
| `dev-server.sh` | Start, check, restart or stop `web-dev-server` on one port |
| `test-summary.sh` | One line per test suite, with the names of failing tests |
| `probe.cjs` | A probe module against a dev page, per theme and direction |
| `probe-compare.cjs` | A diff of two probe result files |
| `ab.sh` | One command on the current tree and on paths from another ref, then a diff |
| `fixup-into.sh` | Folds changes into an earlier branch commit |
| `float-to-tip.sh` | Moves one branch commit to the tip |
| `visual-diffstat.cjs` | Pixel metrics and a contact sheet for failed screenshots |
| `smoke.sh` | Checks the scripts that rewrite a tree |

## Update a skill

The plugin runs from a cached copy of one commit. Commit the change, run
`claude plugin update agent-skills@local`, and start a new session. Create a new skill with
`authoring-skills`.

## Dependencies

- The `gh` CLI, authenticated, for every skill that reads a PR.
- The defaults fit [vaadin/web-components](https://github.com/vaadin/web-components).
