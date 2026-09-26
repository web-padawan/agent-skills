# agent-skills

Private Claude Code plugin with personal skills. The repository is both the plugin and a single-plugin marketplace at its root. You install it from a local path. Nothing is published anywhere.

## Skills

Four review skills with strict boundaries, one verification skill, two source-editing skills, one authoring skill, one meta skill.

| Skill | When to use |
| --- | --- |
| `self-review` | **Your own branch**, before you open or update a PR. Detects the change type (feature / fix / refactor / chore). Runs three passes in one parallel batch. The change pass reviews what the diff does and promises: scope, behavior, fix correctness, plus boundary/impact blocks on the top significant changes. The code pass reviews how the diff is written: logic, conventions, reuse, maintainability, comments. The tests pass reviews the test diff. Never edits code. Classifies findings **A** (must fix before merge) / **B** (follow-up PR) / **C** (taste). Writes a `FINDINGS.md` with a ready / needs-work verdict. Reports coverage gaps and does not close them. `mutation-coverage` closes them. |
| `guided-review` | **Someone else's PR, interactively.** Phase 1 explains the goal and mechanism of the PR with a concrete example. It then gates on your confirmation before Phase 2 reviews thoroughly. Read-only. Never posts. You post any feedback yourself. |
| `adversarial-review` | **Someone else's PR (or your own, pre-review), one skeptical pass.** Produces a report grouped by severity: 🔴 High / 🟠 Medium / 🟡 Low / ✅ Done well, plus a one-line summary. Posts it as a **single PR comment** after confirmation. |
| `pr-review` | **Full reviewer pass with inline comments.** One context-script call, then the three reviewer agents of the plugin in parallel: a change pass and a code pass over the production diff, a tests pass over the test diff. `--deep N` sizes the boundary/impact blocks of the change pass. The plan script writes the shared context file, so the orchestrator reads the plan, not the diff. Triages findings **A** (must fix) / **B** (follow-up) / **C** (nit), the same scale as `self-review`. Presents them behind a short PR summary. After confirmation, posts **positioned line comments** as [Conventional Comments](https://conventionalcomments.org): `issue (behavior, blocking):`, `suggestion (…, non-blocking):`, `question`, `nitpick`, one `praise`. The passes add analysis depth. The triage filter decides what reaches the PR. |
| `mutation-coverage` | Finds code that no test asserts on, via mutation testing (line-removal or Stryker). Then closes each gap with a test that fails when the code is broken. Estimates runtime before it mutates. Commits nothing and installs nothing in the target repo. |
| `refactor-component` | **Moves web component code without a behavior change.** Starts from the mixin chain, because the chain decides where moved code can live. Proves the result with the suites of every package that applies the changed mixin, then per-piece mutation checks. Splits pure motion from a behavior change into two PRs. |
| `comment-cleanup` | **Deletes the comments that say nothing and rewrites the ones that say it badly.** Scopes to a branch diff, one commit, the index, the working tree, one file (`--all`) or one package (`--package`). A diff mode reaches only the comments the change added. A whole-source mode reaches every comment in the files it walks, skips `node_modules`, `dist`, `build`, test directories and `.d.ts` files, and refuses on a dirty tree. Runs the shared DROP / REWRITE / RETAIN policy in `references/comments.md`, the policy that the code pass of the review skills reports against. Drops restated behavior, history, closed tickets and decision records, border conditions the code shows and invariants the types state. Rewrites prose docblocks on private and protected members to `@param` and `@return` tags, moves an inline override note into the docblock leading line, and expands a `#NNNN` shorthand to a full link. Keeps public docblocks, every tag, every directive, every "why not another way" comment and every line that the repo conventions mandate, then shortens each kept one. Edits comment lines only, never code. Gates on your confirmation, with docblock and inline edits offered apart. Proves the run with a comment-lines-only diff check, the type check, a manifest comparison and the package suites. Commits nothing. |
| `pr-description` | **Writes** the PR body. Does not review it. Turns the branch diff into the Vaadin PR template as short bullet lists: issue links, one bullet per behavior change, a `Type of change` label, and numbered `How to test` steps that name a real dev page. Scaffolds `Before / After` for visual changes. Drafts in chat. Runs `gh pr edit` only after you confirm. |
| `authoring-skills` | Meta: create or improve a skill in this plugin. Covers trigger-shaped descriptions, body archetypes, references split, frontmatter conventions. |

## Install

```bash
claude plugin marketplace add /Users/serhii/vaadin/agent-skills
claude plugin install agent-skills@local
```

Verify the install. Then restart the session so that the skills load:

```bash
claude plugin list
```

## Use

```
/agent-skills:self-review                       # current branch, type detected
/agent-skills:self-review <parent-PR-or-issue>  # branch extracted from bigger work
/agent-skills:self-review --feature --deep 2    # force type, boundary/impact blocks on the top 2 changes
/agent-skills:self-review --fix --no-coverage   # type + skip the mutation coverage check
/agent-skills:self-review --scale full          # force full depth on a small diff

/agent-skills:guided-review 9042                # walkthrough first, review after you confirm
/agent-skills:adversarial-review 9042           # skeptical pass → one comment (confirmed first)
/agent-skills:pr-review 9042                    # rubric pass → inline comments (confirmed first)

/agent-skills:mutation-coverage packages/upload/src/vaadin-upload-mixin.js   # one file, line-removal
/agent-skills:mutation-coverage --diff                                       # branch diff, per package

/agent-skills:refactor-component                       # evaluate options for the current package, then sequence them
/agent-skills:refactor-component packages/<name>       # refactor one package

/agent-skills:comment-cleanup                        # comments the branch added, since the merge base
/agent-skills:comment-cleanup --commit HEAD          # comments one commit added
/agent-skills:comment-cleanup --working src/         # comments not committed yet, one path
/agent-skills:comment-cleanup --all src/a-mixin.js   # every comment in one file
/agent-skills:comment-cleanup --package upload       # every comment in packages/upload/src

/agent-skills:pr-description                    # current branch → draft body, apply after you confirm
/agent-skills:pr-description 9042               # rewrite an existing PR's description
```

Run `self-review` on a feature branch with no uncommitted changes to tracked files. Untracked files are fine, and the skill never touches them. The skill refuses on `main` / `master` / `maintenance/*`. Mutation runs cost roughly one suite run per mutant. The skill states the estimate before it starts. It refuses to start silently when the estimate is over about 30 minutes.

### Which review skill?

- For **your own branch** before it becomes a PR, use `self-review`.
- To **understand the PR of another person** before you judge it, use `guided-review`. It posts nothing.
- For a **first-cut skeptical pass** with one summary comment on the PR, use `adversarial-review`.
- For a **full review that leaves actionable line comments** on the PR, use `pr-review`.
- To **describe** the branch rather than judge it, use `pr-description`. It is the only skill that writes a PR body.

Each skill that posts (`adversarial-review`, `pr-review`) asks for confirmation first. Each prefixes its comments with `:robot: AI-generated`. `pr-description` also asks first, but writes the body without any AI attribution. The descriptions that it imitates carry none. Every other skill never writes outside the machine.

### Review profiles (`self-review`, `pr-review`)

The pass list is data, not prose. `references/profiles.md` holds the pass table and the
change type × scale matrix. `scripts/review-plan.sh` resolves them into a launch plan. The
plan holds the type and its signal, and the scale tier and its counts. It lists each pass
with its agent, model, read lane and prompt adds. It also holds the mutant and deep budgets,
the per-pass effort ceiling, the report paths, and the guard verdict.

The script also writes the shared context file that the passes read. That file holds the
framing, the rules, the rubric, the PR body and the lanes. It holds the diff inline when the
diff is small. It holds the conventions chapters that the touched file kinds select, and CI
as a settled fact. The script then prints the literal prompt per pass.

The orchestrator adds its own verified facts in a sibling notes file. It never edits the
skeleton. One script call, nothing for a skill to re-derive. Read `references/profiles.md`
rather than a copy of it here.

The short version: three passes, one per question. `change-reviewer` asks what the
production diff *does and promises*. It checks scope, behavior and compatibility, and fix
correctness, then boundary/impact blocks on the top significant changes. `code-reviewer`
asks how the production diff is *written*. It checks logic, conventions, reuse,
maintainability and comments, on the production diff plus the comment-adjacent hunks.
`test-reviewer` reads the test diff.

The **type** comes from `--fix` / `--feature` / `--refactor` / `--chore`. Without a flag, the
type comes from the PR title prefix, the branch commit subjects, parent issue labels, the
branch name, and the diff shape. The type reaches the change pass as a prompt add. It does
not add a pass. It decides whether fix correctness applies and how strictly the pass reads
behavior preservation. The code pass is type-agnostic.

The **scale** of the diff comes from its production lines: trivial ≤10, lite ≤150, full
above. Scale sizes four things and nothing else:

- the mutation-coverage mutants,
- the deep blocks of the change pass. The deep candidates of the diff cap them further:
  `.d.ts` hunks, new exports, new public methods. `--deep N` overrides that cap,
- the per-pass tool-call ceiling,
- the model per pass. The change pass keeps opus at every tier. Code and tests run on sonnet
  below full.

Public-API changes, weakened test assertions and CI/release files force the full tier
regardless of size.

In `self-review`, the code pass reports C-tier comment and cleanup nits. There they cost
nothing to judge. In `pr-review`, every pass reports a C only when the finding breaks a
quoted convention or a comment is wrong. There the code pass skips the cleanup half. The CI
review bot on the PR deliberately drops those too.

**Deep review** is the second part of the change pass. It selects the top N significant
changes, clustered by decision and ranked by public-surface reach. It returns one block for
each change: boundary, compatibility, named consumers, the promise made, propagation path,
blast radius, and what must be true before merge. It also returns a `Not deep-reviewed` list
of everything below the line. The report keeps the blocks in full for A-tier changes and
condenses the rest.

`self-review` never changes anything. Every step is read-only, with one exception: the
coverage check. That check disables one source line at a time with a comment and restores
the line before the next. A single gate asks whether to write the report and whether to run that
check. It never asks what to apply, because nothing is ever applied. `HEAD`, the index and
the working tree end exactly as they started.

## Shared scripts

The scripts in `scripts/` remove the shell work that a session repeats. Each one prints its
usage with `--help`. Run them from inside the target repository. The skills call them through
`${CLAUDE_PLUGIN_ROOT}/scripts/<name>`. A script with an empty "Used by" cell is a manual
tool for a session that edits its own branch. No skill calls it.

Each script exits with 0 on success, 1 when the work failed, and 2 on a usage or guard
error. `review-plan.sh` is the exception. It exits with 2 when a guard refuses the run.

`gh-context.sh` and `get-pr-context.sh` both read the PR discussion. `gh-context.sh` prints
one item as markdown for a reader. `get-pr-context.sh` prints the anchor SHAs, the CI state
and the sections that the review pipeline parses. Run `scripts/smoke.sh` after a change to a
script that rewrites a tree.

| Script | Does | Used by |
| --- | --- | --- |
| `dev-server.sh` | Starts, checks, restarts or stops the `web-dev-server` on one port. `--check <file>` detects a stale served module after a `git checkout <ref> -- <path>`. | `probe.cjs`, `ab.sh --port` |
| `test-summary.sh` | Runs unit, browser, snapshot, integration or visual suites per `--group` and prints one line per suite plus the failing test names. `--cmd` parses any other command. | `self-review`, `refactor-component` |
| `probe.cjs` | Runs a probe module against a dev page per theme and direction. Gives the module `settle`, `defined`, `layouts` (CDP layout count) and `themeInjected`. Writes one result file with the git head. | `refactor-component` |
| `probe-compare.cjs` | Diffs two probe result files leaf by leaf, with a numeric tolerance. | `refactor-component` |
| `probe-example.cjs` | A probe module to copy. | |
| `gh-context.sh` | Dumps one issue or pull request as markdown: body, linked items, files, comments, reviews, review threads with hunks. | `guided-review`, `adversarial-review`, `pr-description` |
| `ab.sh` | Runs one command on the current tree and on a tree with some paths taken from another ref, restores the paths on every exit, and diffs the two outputs. Never uses `git stash`. | `self-review` (fix revert), `refactor-component` |
| `fixup-into.sh` | Folds staged or named changes into an earlier branch commit and autosquashes without an editor. Aborts on a conflict and keeps the fixup commit on the tip. | |
| `float-to-tip.sh` | Moves one branch commit to the tip and asserts that the tree is unchanged. | |
| `smoke.sh` | Runs `ab.sh`, `fixup-into.sh` and `float-to-tip.sh` in a throwaway repository and checks `--help` of every script. | |
| `get-pr-context.sh` | PR metadata, branch state, anchor SHAs, CI state, existing comment threads, diffs, for the review pipelines. | `review-plan.sh` |
| `review-plan.sh` | Resolves the review profile into a launch plan and writes the shared context skeleton. | `self-review`, `pr-review` |

## Updating a skill

The installed plugin is a **snapshot** in `~/.claude/plugins/cache/local/agent-skills/<sha>/`. The snapshot stays at the commit that you installed it from. An edit in this checkout changes nothing until you refresh the snapshot. Uncommitted edits do not reach the snapshot. Commit first, then run:

```bash
claude plugin marketplace update local   # re-read the marketplace manifest
claude plugin update agent-skills@local  # copy the new commit into the cache
```

The second command prints the sha that it moved from and the sha that it moved to. Restart the session to load the new snapshot.

A direct edit in the cache is the fastest way to try a change mid-session. The next update overwrites the cache. Move any change that you want to keep into this checkout.

New skills follow `authoring-skills`. Start from `skills/authoring-skills/assets/SKILL.template.md`.

## Dependencies

- **`gh` CLI**, authenticated. `guided-review`, `adversarial-review`, `pr-review`, and the PR-context parts of `self-review` require it.
- Nothing else. Every reviewer agent that the pipelines use ships with the plugin in `agents/`. They are read-only subagents (Write/Edit disallowed), invoked as `agent-skills:<name>`.

The skills resolve repo-specific commands (lint, test scoping, source globs) per repo at run time. The defaults fit [vaadin/web-components](https://github.com/vaadin/web-components).

## Layout

```
.claude-plugin/
  plugin.json        # plugin manifest (name: agent-skills)
  marketplace.json   # single-plugin marketplace (name: local)
agents/              # read-only reviewer subagents (agent-skills:<name>) used by the review pipelines
  change-reviewer.md # what the change does and promises: scope, behavior, fix, boundary/impact blocks
  code-reviewer.md   # how the code is written: logic, conventions, reuse, maintainability, comments
  test-reviewer.md   # the test diff
references/          # shared by every review skill — the single source for each of these
  pipeline.md        # the six pipeline steps: plan, context, fan-out, roll call, triage, deliver
  profiles.md        # the pass table + the type x scale matrix (parsed by review-plan.sh)
  severity.md        # A / B / C, the tie-breaker, type-aware tiering, deep-block severities
  delivery.md        # launch rules, the delivery clause, roll call, escalation ladder
  skeleton-blocks.md # the rules and headers review-plan.sh copies into every context skeleton
  rationale.md       # why the pipeline is shaped this way — one line per principle
  retrospective.md   # the runs that taught them: costs, what they exposed, what changed (not loaded)
scripts/
  get-pr-context.sh  # PR metadata, branch state, ANCHORS SHAs, CI, existing comments, diffs
  review-plan.sh     # wraps it and prints === PLAN ===: type, scale, pass list, budgets, paths
  gh-context.sh      # one issue or PR as markdown: body, comments, reviews, threads with hunks
  dev-server.sh      # ensure / restart / status / stop of web-dev-server, stale module check
  test-summary.sh    # one line per suite: counts, status, failing test names, log path
  probe.cjs          # browser probe harness per theme and direction, writes results JSON
  probe-compare.cjs  # leaf-by-leaf diff of two probe result files
  probe-example.cjs  # probe module to copy
  ab.sh              # run a command on HEAD and on <ref> for some paths, restore, diff outputs
  fixup-into.sh      # fold changes into an earlier commit, autosquash without an editor
  float-to-tip.sh    # move one commit to the tip, assert the tree is unchanged
  smoke.sh           # checks of the tree-rewriting scripts in a throwaway repository
skills/
  self-review/
    SKILL.md         # eight steps; shared machinery in references/
    references/      # mutation.md (coverage check), finalize.md (gate, report, verdict)
  guided-review/
    SKILL.md         # two-phase walkthrough, read-only
  adversarial-review/
    SKILL.md         # skeptical pass → one comment grouped by severity
    references/      # canonical output format
  pr-review/
    SKILL.md         # agent-pipeline review → inline comments
    scripts/         # post-comment.sh (gh)
    references/      # comment wording guidelines, single-context fallback
  mutation-coverage/
    SKILL.md         # engine/scope selection + workflow
    scripts/         # mutate.mjs (line-removal), stryker-diff.mjs (PR-diff mode)
    assets/stryker/  # config templates materialized into the target repo
    references/      # stryker procedure, survivor taxonomy
  refactor-component/
    SKILL.md         # map, place, move, prove, deliver
    references/      # mixin-placement.md, verification.md, delivery.md
  pr-description/
    SKILL.md         # gather → classify → draft → deliver (confirmation-gated)
    references/      # TEMPLATE.md (output skeleton), STYLE.md (bullet voice, anti-patterns)
  authoring-skills/
    SKILL.md         # description-first authoring workflow
    references/      # descriptions.md, frontmatter.md, skill-types.md, agents.md
    assets/          # SKILL.template.md
```
