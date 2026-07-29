# agent-skills

Private Claude Code plugin with personal skills. The repository is both the plugin and a single-plugin marketplace at its root, installed from a local path — nothing is published anywhere.

## Skills

| Skill | What it does |
| --- | --- |
| `self-review` | Reviews the current branch before opening or updating a PR: general review, scope, direction, simplification, integration, tests + mutation check, slop cleanup. Applies fixes in a single commit and writes a findings report with a ready / needs-work verdict. |

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
/agent-skills:self-review                      # current branch
/agent-skills:self-review <parent-PR-or-issue>  # branch extracted from bigger work
```

Run it on a feature branch with a clean working tree. It refuses on `main` / `master` / `maintenance/*`.

## Updating a skill

Edit the files here and commit — an installed local-path marketplace reads from this checkout, so a session restart picks the change up. `claude plugin marketplace update local` refreshes the listing if a manifest changed.

## Dependencies

`self-review` delegates to [oh-my-claudecode](https://github.com/mikeyobrien/oh-my-claudecode) agents (`code-reviewer`, `test-engineer`, `ai-slop-cleaner`) and the built-in `simplify` skill. Without OMC it falls back to `general-purpose` agents with the same prompts.

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
