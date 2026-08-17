# agent-skills

Private Claude Code plugin with personal skills. The repository is both the plugin and a single-plugin marketplace at its root, installed from a local path — nothing is published anywhere.

## Skills

Five review skills with strict boundaries, one verification skill, one authoring skill, one meta skill.

| Skill | When to use |
| --- | --- |
| `self-review` | **Your own branch**, before opening or updating a PR. Detects the change type (feature / fix / refactor / chore), runs the matching profile of breadth passes, then gives every *significant change* the three `arch-review` lenses. Never edits code — classifies findings **A** (must fix before merge) / **B** (follow-up PR) / **C** (taste) and writes a `FINDINGS.md` with a ready / needs-work verdict. Coverage gaps are reported, not closed — `mutation-coverage` closes them. |
| `arch-review` | **One change, deep.** Three lenses — architectural (observed behavior, risk, consequences, suggestion), boundary (which promise the change makes, to whom, why it is hard to take back), change-impact analysis (ripple effects, propagation paths, unblock conditions). Takes a file, a diff range, a PR, or the current branch. Answers "is this API safe to ship?", "what's the blast radius?". Report-only. Also the deep-review engine inside `self-review`. |
| `guided-review` | **Someone else's PR, interactively.** Phase 1 explains the PR's goal and mechanism with a concrete example, then gates on your confirmation before Phase 2 reviews thoroughly. Read-only — never posts; you post any feedback yourself. |
| `adversarial-review` | **Someone else's PR (or your own, pre-review), one skeptical pass.** Severity-bucketed report (🔴 High / 🟠 Medium / 🟡 Low / ✅ Done well + one-line summary), posted as a **single PR comment** after confirmation. |
| `pr-review` | **Full reviewer pass with inline comments.** Rubric review (correctness / security / maintainability / performance, P0–P3), findings presented in chat, then **positioned line comments** posted after confirmation. |
| `mutation-coverage` | Finds code no test asserts on via mutation testing (line-removal or Stryker), then closes each gap with a test that fails when the code is broken. Estimates runtime before mutating; nothing committed or installed in the target repo. |
| `pr-description` | **Writes** the PR body, doesn't review it. Turns the branch diff into the Vaadin PR template as short bullet lists — issue links, one bullet per behavior change, a `Type of change` label, and numbered `How to test` steps naming a real dev page. Scaffolds `Before / After` for visual changes. Drafts in chat; `gh pr edit` only after you confirm. |
| `authoring-skills` | Meta: create or improve a skill in this plugin — trigger-shaped descriptions, body archetypes, references split, frontmatter conventions. |

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
/agent-skills:self-review --feature --deep 2    # force type, cap the deep review
/agent-skills:self-review --fix --no-coverage   # type + skip the mutation coverage check

/agent-skills:arch-review packages/overlay/src/vaadin-overlay-mixin.js:120-180
/agent-skills:arch-review --diff main..feature  # inventory + trio per significant change
/agent-skills:arch-review 9042                  # a PR, read-only

/agent-skills:guided-review 9042                # walkthrough first, review after you confirm
/agent-skills:adversarial-review 9042           # skeptical pass → one comment (confirmed first)
/agent-skills:pr-review 9042                    # rubric pass → inline comments (confirmed first)

/agent-skills:mutation-coverage packages/upload/src/vaadin-upload-mixin.js   # one file, line-removal
/agent-skills:mutation-coverage --diff                                       # branch diff, per package

/agent-skills:pr-description                    # current branch → draft body, apply after you confirm
/agent-skills:pr-description 9042               # rewrite an existing PR's description
```

Run `self-review` on a feature branch with no uncommitted changes to tracked files (untracked files are fine and are never touched). It refuses on `main` / `master` / `maintenance/*`. Mutation runs cost roughly one suite run per mutant; the skill states the estimate before starting and refuses to silently start anything over ~30 minutes.

### Which review skill?

- Reviewing **your own branch** before it becomes a PR → `self-review`.
- A pointed **architecture / API / impact question** about one change → `arch-review`.
- **Understanding someone's PR** before judging it, posting nothing → `guided-review`.
- A **first-cut skeptical pass**, one summary comment on the PR → `adversarial-review`.
- A **full review leaving actionable line comments** on the PR → `pr-review`.
- **Describing** the branch rather than judging it → `pr-description` (the only one that writes a PR body).

Everything that posts (`adversarial-review`, `pr-review`) asks for confirmation first and prefixes comments with `:robot: AI-generated`. `pr-description` also asks first, but writes the body without any AI attribution — the descriptions it imitates carry none. Everything else never writes outside the machine.

### Review profiles (`self-review`)

The change type comes from, in order: an explicit `--fix` / `--feature` / `--refactor` / `--chore` flag, the PR title's conventional prefix, the branch's commit subjects, parent issue labels, the branch name, then the shape of the diff. It decides how much review the branch gets:

| Type | Extra pass | Deep review | Mutants |
| --- | --- | --- | --- |
| **feature** | requirements coverage | 6 significant changes | 15 |
| **fix** | root cause & blast radius, regression test must fail without the fix | 3, including the fix's own hunks | 5, on the fix |
| **refactor** | behavior preservation | 4, weighted to moved boundaries | 10 |
| **chore** | — | none | none |

**Deep review** is the per-change part, powered by `arch-review`'s lens contracts. A *significant change* is a hunk that touches public surface, adds a module, changes control flow, changes a cross-module contract, or moves logic across a boundary — never tests, docs, config, or formatting. Changes are ranked and capped at the budget; anything below the line is listed in the report rather than dropped quietly.

`self-review` never changes anything. Every stage is read-only, the one exception being the coverage check, which comments out a source line at a time and restores it before the next. A single gate asks whether to write the report and whether to run that check — never what to apply, because nothing is ever applied. `HEAD`, the index and the working tree end exactly as they started.

## Updating a skill

The installed plugin is a **snapshot** copied to `~/.claude/plugins/cache/local/agent-skills/<sha>/`, pinned to the commit it was installed from — editing this checkout changes nothing until the snapshot is refreshed. Commit first (uncommitted edits are not picked up), then:

```bash
claude plugin marketplace update local   # re-read the marketplace manifest
claude plugin update agent-skills@local  # copy the new commit into the cache
```

The second command prints the sha it moved from and to. Restart the session to load it.

Editing the cache directly is the fastest way to try a change mid-session, but the next update overwrites it — port anything worth keeping back here.

New skills follow `authoring-skills` — start from `skills/authoring-skills/assets/SKILL.template.md`.

## Dependencies

- **`gh` CLI**, authenticated — required by `guided-review`, `adversarial-review`, `pr-review`, and the PR-context parts of `self-review` / `arch-review`.
- **oh-my-claudecode** (optional) — `self-review` and `arch-review` delegate to its agents (`code-reviewer`, `test-engineer`, `architect`, `critic`, `debugger`, `ai-slop-cleaner`); without OMC they fall back to `general-purpose` agents with the same prompts.

Repo-specific commands (lint, test scoping, source globs) are resolved per repo at run time; the defaults are tuned for [vaadin/web-components](https://github.com/vaadin/web-components).

## Layout

```
.claude-plugin/
  plugin.json        # plugin manifest (name: agent-skills)
  marketplace.json   # single-plugin marketplace (name: local)
skills/
  self-review/
    SKILL.md         # stage orchestration; lens/significance contracts live in arch-review
    references/      # per-stage detail, read on first use
  arch-review/
    SKILL.md         # standalone entry: scope → inventory → trio → triage
    references/      # lenses.md (field contracts), significance.md (inventory rules)
  guided-review/
    SKILL.md         # two-phase walkthrough, read-only
  adversarial-review/
    SKILL.md         # skeptical pass → one severity-bucketed comment
    references/      # canonical output format
  pr-review/
    SKILL.md         # rubric review → inline comments
    scripts/         # get-pr-context.sh, post-comment.sh (gh)
    references/      # comment wording guidelines
  mutation-coverage/
    SKILL.md         # engine/scope selection + workflow
    scripts/         # mutate.mjs (line-removal), stryker-diff.mjs (PR-diff mode)
    assets/stryker/  # config templates materialized into the target repo
    references/      # stryker procedure, survivor taxonomy
  pr-description/
    SKILL.md         # gather → classify → draft → deliver (confirmation-gated)
    references/      # TEMPLATE.md (output skeleton), STYLE.md (bullet voice, anti-patterns)
  authoring-skills/
    SKILL.md         # description-first authoring workflow
    references/      # descriptions.md, frontmatter.md, skill-types.md
    assets/          # SKILL.template.md
```
