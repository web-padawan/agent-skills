# agent-skills

Private Claude Code plugin with personal skills. The repository is both the plugin and a single-plugin marketplace at its root, installed from a local path — nothing is published anywhere.

## Skills

| Skill | What it does |
| --- | --- |
| `self-review` | Reviews the current branch before opening or updating a PR. Detects the change type and runs the matching profile — a feature also gets API-design, requirements-coverage and architecture passes, a fix gets root-cause, blast-radius and regression-test checks, a chore gets a short pass. Classifies findings **A** (must fix before merge) / **B** (follow-up PR) / **C** (taste), asks which tiers to apply, and leaves approved fixes staged but never committed, with a findings report and a ready / needs-work verdict. |

## Install

```bash
claude plugin marketplace add /Users/serhii/vaadin/agent-skills
claude plugin install agent-skills@local
```

Verify, then restart the session so skills load:

```bash
claude plugin list
```

## Use

```
/agent-skills:self-review                       # current branch, type detected
/agent-skills:self-review <parent-PR-or-issue>  # branch extracted from bigger work
/agent-skills:self-review --feature             # force the change type
/agent-skills:self-review --fix --no-arch       # type + architecture pass off
```

Run it on a feature branch with no uncommitted changes to tracked files (untracked files are fine and are never touched). It refuses on `main` / `master` / `maintenance/*`.

### Review profiles

The change type comes from, in order: an explicit `--fix` / `--feature` / `--refactor` / `--chore` flag, the PR title's conventional prefix, the branch's commit subjects, parent issue labels, the branch name, then the shape of the diff. It decides how much review the branch gets:

| Type | Extra passes | Architecture | Mutants |
| --- | --- | --- | --- |
| **feature** | API design, requirements coverage | always | 15 |
| **fix** | root cause & blast radius, regression test must fail without the fix | only when it adds a module or API | 5, on the fix |
| **refactor** | behavior preservation | when modules move | 10 |
| **chore** | — | never | none |

It never commits: analysis is read-only, a single approval gate asks which severity tiers to apply, and approved fixes end up **staged** for you to review with `git diff --staged` and commit yourself (`git reset` unstages).

## Updating a skill

Edit the files here and commit — an installed local-path marketplace reads from this checkout, so a session restart picks the change up. `claude plugin marketplace update local` refreshes the listing if a manifest changed.

## Dependencies

`self-review` delegates to [oh-my-claudecode](https://github.com/mikeyobrien/oh-my-claudecode) agents (`code-reviewer`, `test-engineer`, `architect`, `debugger`, `ai-slop-cleaner`) and the built-in `simplify` skill. Without OMC it falls back to `general-purpose` agents with the same prompts.

Repo-specific commands (lint, test scoping, source globs, commit-message rules) are resolved per repo in phase 0; the defaults are tuned for [vaadin/web-components](https://github.com/vaadin/web-components).

## Layout

```
.claude-plugin/
  plugin.json        # plugin manifest (name: agent-skills)
  marketplace.json   # single-plugin marketplace (name: local)
skills/
  self-review/
    SKILL.md         # phase orchestration
    references/      # per-phase detail, read on first use
```
