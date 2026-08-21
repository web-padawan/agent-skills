# agent-skills

Private Claude Code plugin with personal skills. The repository is both the plugin and a single-plugin marketplace at its root, installed from a local path — nothing is published anywhere.

## Skills

Five review skills with strict boundaries, one verification skill, one authoring skill, one meta skill.

| Skill | When to use |
| --- | --- |
| `self-review` | **Your own branch**, before opening or updating a PR. Detects the change type (feature / fix / refactor / chore) and runs the matching profile of breadth passes — the comment/slop pass always included — in one parallel batch. Never edits code — classifies findings **A** (must fix before merge) / **B** (follow-up PR) / **C** (taste) and writes a `FINDINGS.md` with a ready / needs-work verdict. Coverage gaps are reported, not closed — `mutation-coverage` closes them. Per-change deep review lives in `arch-review`; `--deep N` opts in from here. |
| `arch-review` | **One change, deep.** Three lenses — architectural (observed behavior, risk, consequences, suggestion), boundary (which promise the change makes, to whom, why it is hard to take back), change-impact analysis (ripple effects, propagation paths, unblock conditions). Takes a file, a diff range, a PR, or the current branch. Answers "is this API safe to ship?", "what's the blast radius?". Report-only. The plugin's only home of the lens deep review — `self-review --deep` delegates here. |
| `guided-review` | **Someone else's PR, interactively.** Phase 1 explains the PR's goal and mechanism with a concrete example, then gates on your confirmation before Phase 2 reviews thoroughly. Read-only — never posts; you post any feedback yourself. |
| `adversarial-review` | **Someone else's PR (or your own, pre-review), one skeptical pass.** Severity-bucketed report (🔴 High / 🟠 Medium / 🟡 Low / ✅ Done well + one-line summary), posted as a **single PR comment** after confirmation. |
| `pr-review` | **Full reviewer pass with inline comments.** One context-script call, then the plugin's reviewer agents in parallel (correctness, tests, comment slop, conventions, plus the change type's profile pass: premise on fixes, requirements + scope on features, behavior preservation on refactors; `--deep N` adds arch-review's lenses) — the diff never enters the orchestrator's context. Findings triaged **A** (must fix) / **B** (follow-up) / **C** (nit) — the same scale as `self-review` — presented behind a short PR summary, then **positioned line comments** posted after confirmation. Profile passes add analysis depth; the triage filter decides what reaches the PR. |
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
/agent-skills:self-review --feature --deep 2    # force type, opt into arch-review deep review (top 2 changes)
/agent-skills:self-review --fix --no-coverage   # type + skip the mutation coverage check
/agent-skills:self-review --scale full          # force full depth on a small diff

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

| Type | Extra pass | Agents | Mutants |
| --- | --- | --- | --- |
| **feature** | cleanup + requirements coverage | 8 | 15 |
| **fix** | premise & history first (a fix contradicting a recorded project decision stops the run), then root cause & blast radius; regression test must fail without the fix | 5, hard cap | 5, on the fix |
| **refactor** | cleanup + behavior preservation | 7 | 10 |
| **chore** | — | 4 | none |

Every profile includes the comment/slop pass. Feature and refactor also run a cleanup pass (reuse / simplification / efficiency) — `self-review` is the full-scale review that surfaces even C-tier nits, because the CI review bot on the PR is a final gate that deliberately drops low-value findings. `pr-review` reuses the type detection and the profile's breadth pass (not the mutant budget or the cleanup pass) when reviewing a PR; on a fix PR a contradicted premise leads the findings instead of stopping the run.

On top of the type, the diff's **scale** tiers the depth: **trivial** (≤10 lines) runs 1–3 agents with the dropped passes' questions folded into the general pass, **lite** (≤100 lines) runs 3–4 (a fix always keeps its 5), **full** (>100 lines) is the table above. Public-API changes, weakened test assertions, and CI/release files force full regardless of size; `--scale trivial|lite|full` forces a tier by hand. Mutant budgets cap at 3 / 8 / type budget, and the fix profile's whole-fix revert runs at every scale.

**Deep review** — the per-change lens analysis — is `arch-review`'s job: by default `self-review` reports breadth findings only and points at `/agent-skills:arch-review` for architectural questions; `--deep N` runs arch-review's inventory and lens trios on the branch's top N significant changes and merges their findings into the report.

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
- Nothing else: every reviewer agent the pipelines use ships with the plugin in `agents/` — read-only subagents (Write/Edit disallowed) invoked as `agent-skills:<name>`.

Repo-specific commands (lint, test scoping, source globs) are resolved per repo at run time; the defaults are tuned for [vaadin/web-components](https://github.com/vaadin/web-components).

## Layout

```
.claude-plugin/
  plugin.json        # plugin manifest (name: agent-skills)
  marketplace.json   # single-plugin marketplace (name: local)
agents/              # read-only reviewer subagents (agent-skills:<name>) used by the review pipelines
  lens-*.md          # the three arch-review lenses
  *-reviewer.md      # breadth passes (self-review + pr-review), premise check, comment/slop pass
  change-enumerator.md
scripts/
  get-pr-context.sh  # shared context script: PR metadata, branch state, ANCHORS SHAs, diffs
skills/
  self-review/
    SKILL.md         # stage orchestration; deep review delegated to arch-review via --deep
    references/      # per-stage detail, read on first use
  arch-review/
    SKILL.md         # standalone entry: scope → inventory → trio → triage
    references/      # lenses.md, significance.md, delivery.md (shared launch/roll-call rules)
  guided-review/
    SKILL.md         # two-phase walkthrough, read-only
  adversarial-review/
    SKILL.md         # skeptical pass → one severity-bucketed comment
    references/      # canonical output format
  pr-review/
    SKILL.md         # agent-pipeline review → inline comments
    scripts/         # post-comment.sh (gh)
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
    references/      # descriptions.md, frontmatter.md, skill-types.md, agents.md
    assets/          # SKILL.template.md
```
