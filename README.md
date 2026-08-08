# agent-skills

Private Claude Code plugin with personal skills. The repository is both the plugin and a single-plugin marketplace at its root, installed from a local path — nothing is published anywhere.

## Skills

| Skill | What it does |
| --- | --- |
| `self-review` | Reviews the current branch before opening or updating a PR. Detects the change type and runs the matching profile — a feature also gets a requirements-coverage pass, a fix gets root-cause, blast-radius and regression-test checks, a chore gets a short pass. Then gives every *significant change* three structured reviews: **architectural** (observed behavior, risk, consequences, suggestion), **boundary** (which boundary, whose consumers, what promise, why it is hard to take back), and **change-impact analysis** (ripple effects, propagation paths, mitigation, unblock conditions). **Never edits code**: classifies findings **A** (must fix before merge) / **B** (follow-up PR) / **C** (taste) and writes a `FINDINGS.md` with a ready / needs-work verdict. Coverage gaps are reported, not closed — `mutation-coverage` closes them. |
| `mutation-coverage` | Finds code no test asserts on via mutation testing, then closes each gap with a test that fails when the code is broken. Two engines: a zero-setup line-removal runner (default for a single file) and Stryker (`--diff` pre-PR mode, whole packages, or `--stryker`) run via `npx` with config materialized as untracked files — nothing is committed or installed in the target repo. Estimates runtime before mutating, classifies survivors (coverage gap / masked write / self-referential assertion / unkillable), and ends with a report mapping each killed survivor to its new test. |

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
/agent-skills:self-review --deep 2              # cap the deep review at 2 significant changes
/agent-skills:self-review --fix --no-coverage   # type + skip the mutation coverage check
```

Run it on a feature branch with no uncommitted changes to tracked files (untracked files are fine and are never touched). It refuses on `main` / `master` / `maintenance/*`.

```
/agent-skills:mutation-coverage packages/upload/src/vaadin-upload-mixin.js   # one file, line-removal
/agent-skills:mutation-coverage <file> --stryker                             # one file, Stryker operators
/agent-skills:mutation-coverage --diff                                       # branch diff vs origin/main, per package
/agent-skills:mutation-coverage --package accordion                          # whole package, background job
```

Mutation runs cost roughly one suite run per mutant; the skill states the estimate before starting and refuses to silently start anything over ~30 minutes.

### Review profiles

The change type comes from, in order: an explicit `--fix` / `--feature` / `--refactor` / `--chore` flag, the PR title's conventional prefix, the branch's commit subjects, parent issue labels, the branch name, then the shape of the diff. It decides how much review the branch gets:

| Type | Extra pass | Deep review | Mutants |
| --- | --- | --- | --- |
| **feature** | requirements coverage | 6 significant changes | 15 |
| **fix** | root cause & blast radius, regression test must fail without the fix | 3, including the fix's own hunks | 5, on the fix |
| **refactor** | behavior preservation | 4, weighted to moved boundaries | 10 |
| **chore** | — | none | none |

**Deep review** is the per-change part. A *significant change* is a hunk that touches public surface, adds a module, changes control flow, changes a cross-module contract, or moves logic across a boundary — never tests, docs, config, or formatting. Changes are ranked and capped at the budget; anything below the line is listed in the report rather than dropped quietly.

It never changes anything. Every stage is read-only, the one exception being the coverage check, which comments out a source line at a time and restores it before the next. A single gate asks whether to write the report and whether to run that check — never what to apply, because nothing is ever applied. `HEAD`, the index and the working tree end exactly as they started.

## Updating a skill

The installed plugin is a **snapshot** copied to `~/.claude/plugins/cache/local/agent-skills/<sha>/`, pinned to the commit it was installed from — editing this checkout changes nothing until the snapshot is refreshed. Commit first (uncommitted edits are not picked up), then:

```bash
claude plugin marketplace update local   # re-read the marketplace manifest
claude plugin update agent-skills@local  # copy the new commit into the cache
```

The second command prints the sha it moved from and to. Restart the session to load it.

Editing the cache directly is the fastest way to try a change mid-session, but the next update overwrites it — port anything worth keeping back here.

## Dependencies

`self-review` delegates to [oh-my-claudecode](https://github.com/mikeyobrien/oh-my-claudecode) agents (`code-reviewer`, `test-engineer`, `architect`, `critic`, `debugger`, `ai-slop-cleaner`). Without OMC it falls back to `general-purpose` agents with the same prompts.

Repo-specific commands (lint, test scoping, source globs) are resolved per repo in stage 0; the defaults are tuned for [vaadin/web-components](https://github.com/vaadin/web-components).

## Layout

```
.claude-plugin/
  plugin.json        # plugin manifest (name: agent-skills)
  marketplace.json   # single-plugin marketplace (name: local)
skills/
  self-review/
    SKILL.md         # phase orchestration
    references/      # per-phase detail, read on first use
  mutation-coverage/
    SKILL.md         # engine/scope selection + workflow
    scripts/         # mutate.mjs (line-removal), stryker-diff.mjs (PR-diff mode)
    assets/stryker/  # config templates materialized into the target repo
    references/      # stryker procedure, survivor taxonomy
```
