# agent-skills

Private Claude Code plugin with personal skills. The repository is both the plugin and a single-plugin marketplace at its root, installed from a local path — nothing is published anywhere.

## Skills

| Skill | What it does |
| --- | --- |
| `self-review` | Reviews the current branch before opening or updating a PR: general review, scope, direction, integration, tests + coverage check, simplification and slop passes, plus an architecture pass on bigger diffs. Classifies findings **A** (must fix before merge) / **B** (follow-up PR) / **C** (taste), asks which tiers to apply, and leaves approved fixes staged but never committed, with a findings report and a ready / needs-work verdict. |

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
/agent-skills:self-review                       # current branch
/agent-skills:self-review <parent-PR-or-issue>  # branch extracted from bigger work
/agent-skills:self-review --arch                # force the architecture pass on
/agent-skills:self-review --no-arch             # force it off
```

Run it on a feature branch with no uncommitted changes to tracked files (untracked files are fine and are never touched). It refuses on `main` / `master` / `maintenance/*`.

It never commits: analysis is read-only, a single approval gate asks which severity tiers to apply, and approved fixes end up **staged** for you to review with `git diff --staged` and commit yourself (`git reset` unstages).

## Updating a skill

Edit the files here and commit — an installed local-path marketplace reads from this checkout, so a session restart picks the change up. `claude plugin marketplace update local` refreshes the listing if a manifest changed.

## Dependencies

`self-review` delegates to [oh-my-claudecode](https://github.com/mikeyobrien/oh-my-claudecode) agents (`code-reviewer`, `test-engineer`, `architect`, `ai-slop-cleaner`) and the built-in `simplify` skill. Without OMC it falls back to `general-purpose` agents with the same prompts.

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
