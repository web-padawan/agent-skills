---
name: self-review
description: Self-review the current branch (or its open PR) before opening or updating a PR. Detects the change type — bug fix, feature, refactor, chore — and runs the matching profile of breadth review passes in one parallel batch, always including the comment/slop pass; a bug fix first has its premise checked against the history of the behavior it changes. Never edits code — classifies findings A (must fix before merge) / B (follow-up) / C (taste) and writes a FINDINGS.md report with a ready / needs-work verdict. Per-change deep review (lenses) lives in arch-review — opt in here with --deep N. Use on your own branch; not for reviewing someone else's PR (guided-review, pr-review, adversarial-review) or a single pointed architecture question (arch-review).
argument-hint: "[parent-PR-or-issue-url] [--fix|--feature|--refactor|--chore] [--deep N] [--no-coverage]"
disable-model-invocation: true
allowed-tools: Read, Write, Edit, Glob, Grep, Task, Agent, SendMessage, Skill, AskUserQuestion, Bash(git:*), Bash(gh:*), Bash(yarn:*), Bash(npm:*), Bash(npx:*), Bash(pnpm:*)
---

You are self-reviewing the current branch before it becomes (or updates) a PR. Optional input `$0` is the parent PR or issue this branch was extracted from. Work the stages in order.

Three rules outrank everything else:

- **Never edit code.** Every stage is read-only. The single carve-out is stage 4's coverage mutants: one line at a time, restored with `git checkout -- <path>` before the next, and the stage ends only when `git status --porcelain --untracked-files=no` is empty again. Nothing else in this skill writes to a tracked file. (`Edit` is in `allowed-tools` for that carve-out alone — do not remove it, and do not use it anywhere else.)
- **Never commit or stage.** No commit, amend, push, `git add`, `stash`, `reset --hard`, or `git clean` — ever. `HEAD` and the index end exactly as found.
- **The only files this skill creates are the shared context file and the report**, both in the git-ignored report directory, and the report only after the stage-3 gate — or, on a premise-stopped fix, the premise-stop question that stands in for it — approves it.

Every finding ends up in the report as `confirmed` or `accepted`. Nothing is silently dropped.

Detailed instructions live in references — read each one the **first time** a stage needs it, and never twice in a session. `analysis.md`, `fix-profile.md`, `triage.md`, `mutation.md` and `finalize.md` sit next to this file (fallback `${CLAUDE_PLUGIN_ROOT}/skills/self-review/references/<name>.md`); `delivery.md` belongs to the sibling `arch-review` skill (fallback `${CLAUDE_PLUGIN_ROOT}/skills/arch-review/references/<name>.md`).

| Reference | Covers |
| --- | --- |
| [`references/analysis.md`](references/analysis.md) | Stage 1: breadth-pass prompts per profile (incl. the premise pass's procedure), context file, finding format, severity rubric |
| [`references/fix-profile.md`](references/fix-profile.md) | Fix only: launch order, premise decision rules, the premise-stop gate, five-agent cap, size check |
| [`../arch-review/references/delivery.md`](../arch-review/references/delivery.md) | Launch rules, the delivery clause, roll call, escalation ladder |
| [`references/triage.md`](references/triage.md) | Stages 2–3: verification, classification, the gate |
| [`references/mutation.md`](references/mutation.md) | Stage 4: mutant selection per profile, restore safety, survivors as findings |
| [`references/finalize.md`](references/finalize.md) | Stage 5: FINDINGS.md template, verdict rubric |

## Stage 0 — Setup & guards

- Refuse to run on `main`, `master`, or a `maintenance/*` branch — stop with a one-line message.
- **Tracked files must be clean**: `git status --porcelain --untracked-files=no` empty. If not, stop and ask the user to commit or stash first. Untracked files are fine — never touch them, never stage them. This is not tidiness: stage 4 restores a mutant with `git checkout -- <path>`, which resets the file to the **index**. Because this skill never stages anything, the index equals `HEAD`, so that restore is exact and total. A dirty tree breaks the invariant the carve-out rests on.
- **Context in one call**: run the shared context script — `${CLAUDE_PLUGIN_ROOT}/scripts/get-pr-context.sh --no-diff`, with the plugin root resolved to a literal path. It returns the branch's open PR (title/body feed the intent check), the branch state, and the `=== ANCHORS ===` section: the merge-base SHA — record it as `<BASE>`, always substituted as the literal SHA (shell variables do not persist between tool calls, and subagents never see them) — plus the changed-file list. Fetch `$0` (parent PR/issue) with `gh` when given.
- Record `<HEAD0>` = `git rev-parse HEAD`. Stage 5 asserts `HEAD` still equals it and that the index is still empty — that is the proof nothing was committed or staged.
- **Command map** — record once, used by stage 4. In `vaadin/web-components`: lint `yarn lint`; tests `yarn test --group <package>`; source glob `packages/*/src/*.js`; affected packages = unique `packages/<name>` prefixes of the changed files. In another repo, take lint/test commands from `CLAUDE.md` / `AGENTS.md` / `package.json` scripts and note the equivalent source glob and test-scoping unit.
- **Report location**: `.omc/self-review/<slug>-FINDINGS.md` when `.omc/` is git-ignored (`git check-ignore -q .omc` — true in web-components); otherwise the session scratchpad, so the report never lands in the diff. `<slug>` is the branch name with `/` replaced by `-` — branch names are usually `type/topic`, and using them raw silently creates a directory per prefix. The shared context file sits next to it as `context.md`.

### Change type

Decide the type once, from the first signal that resolves — do not spend a subagent on this:

1. `--fix` / `--feature` / `--refactor` / `--chore` flag.
2. Conventional prefix of the PR title (`fix:`, `feat:`, `refactor:`, `perf:`, `test:`, `docs:`, `chore:`, `build:`, `deps:`).
3. Majority prefix across `git log --format=%s <BASE>..HEAD`.
4. Parent issue labels from `$0` (`bug` → fix, `enhancement` / `feature` → feature).
5. Branch name prefix (`fix/`, `bugfix/`, `feat/`, `refactor/`).
6. Diff shape: new export, public property, method, or `.d.ts` addition → feature; edits inside existing logic plus a test → fix; same behavior moved or renamed → refactor; only tests, docs, or build files → chore.

Take the **first signal that resolves** and stop — that is the declared type, and it is what the profile runs on. `perf:` maps to refactor.

Signals below it may still *disagree*; do not let that silently upgrade the type. Instead, when a lower signal is more demanding than the one that won (`feat` beats `fix` beats `refactor` beats `chore`), keep the declared type and hand the disagreement to the scope pass as an explicit question. A branch whose PR title says `refactor:` while two of its three commits say `fix:` is exactly that case. Two reasons to keep the declared type rather than auto-upgrading: the declared type is what the author is asking reviewers to believe, so reviewing against it is what tests the claim; and the more demanding profile would examine a *different* risk instead of the mislabel itself.

Report the type and the signal that decided it in the stage-5 summary, and treat a wrong-looking type as a `scope` finding — a fix that grows an API is a mislabeled feature, and a refactor that removes public API is a mislabeled breaking change.

### Review profile

The type picks the profile. Passes are named, never numbered — analysis.md's pass table maps each name to its agent, and every pass's contract lives in that agent's definition. The **slop** pass runs for every type — a fix included.

| Type | Breadth passes | Agents | Mutant budget |
| --- | --- | --- | --- |
| **feature** | general · scope · intent · integration · tests · slop · **requirements coverage** | 7 | 15 |
| **fix** | **premise & history** first, then general · tests · slop · **root cause & blast radius** — **5 agents total, hard cap** | 5 | 5, concentrated on the fix |
| **refactor** | general · scope · integration · tests · slop · **behavior preservation** | 6 | 10 |
| **chore** | general · integration · tests · slop | 4 | none — skip stage 4 |

- `--no-coverage` zeroes the mutant budget and skips the gate's coverage question.
- Say in the summary which profile ran.
- The agent counts are floors for coverage, not targets to trim: on a small diff the saving comes from passes not re-deriving each other's work (analysis.md's **Settled facts** and **Open leads** rules), not from dropping a pass. The one exception is repo-wide work — the root-cause/blast-radius pass scales with the repo, not the diff, and is never the place to economise.

### Deep review — arch-review's job, opt-in here

This skill runs **no per-change deep review**: the lens trio, the significance inventory, and their contracts all live in the sibling `arch-review` skill. The general pass still covers correctness and API-contract keeping across the whole diff; for architectural shape, boundary promises, or blast radius of a specific change, the report points the user at `/agent-skills:arch-review <file:lines>`.

`--deep N` opts back in: after stage 1's breadth barrier, run arch-review's inventory and lens trios exactly as [`../arch-review/SKILL.md`](../arch-review/SKILL.md) steps 2–3 describe (budget N, its batching cap, delivery per delivery.md), and merge the resulting findings into stage-2 triage. Do not restate any of arch-review's machinery here — its SKILL.md is the single source.

### Fix profile — premise first, five agents total

The fix pipeline differs end to end — read [`references/fix-profile.md`](references/fix-profile.md) before stage 1 on a fix. In short:

- **The premise & history pass runs before the rest of stage 1**, after the context file is written, and answers one question: does the project already have a decision about this behavior? `sound` / `unverified` → continue. **`contradicted` → stop the review**: report the citation and ask the user with `AskUserQuestion` — that question stands in for the stage-3 gate, and stages 1–4 never run.
- **Five agents total, hard cap**: premise & history, then a single stage-1 message of **four** — general (carrying the folded scope, intent and integration questions), tests, root cause & blast radius, and slop.
- The premise pass runs alone and first, so its evidence is available to every later pass — append its citations to the context file's **Settled facts** before launching the rest, or the four that follow will each re-derive them.

## Stage 1 — Analysis (read-only)

Per analysis.md: write the shared context file, then launch the profile's breadth passes — **all in one message**, sharing one barrier. Every pass runs as a plugin agent (`agent-skills:*`); each agent's definition carries its contract, so prompts carry only the context file path, the pass table's run-specific facts, and the delivery clause.

On a **fix** this is a single message of **four** agents — general, tests, root-cause and slop — launched only after the premise check returned `sound` or `unverified` (on `contradicted` the run stopped; see fix-profile.md).

Read delivery.md before launching and follow it exactly — `run_in_background: false`, no `name`, and the delivery clause in every prompt. Those three are what decide whether the findings ever reach you; the defaults silently lose them.

With `--deep N`: when the breadth barrier returns, run arch-review's steps 2–3 (see **Deep review** above) before moving to stage 2.

Afterwards assert `git status --porcelain --untracked-files=no` is still empty. If any pass edited anyway: revert those tracked files with `git checkout -- <path>` (safe — the tree was clean at stage 0), delete files it created **by path**, and keep only its output as findings. Never `git clean`; never touch pre-existing untracked files.

Then run delivery.md's **roll call**: list every agent launched by pass name — never by number — with its finding count, recover the ones that reported nothing by escalating the mechanism per delivery.md's ladder, and record each pass as `agent`, `self-run`, or `missing`. A pass that reported nothing has *not* come back clean.

## Stage 2 — Triage & classify (read-only)

Per triage.md: verify every finding against the code, dedup across the passes, assign the final tier, note the suggested one-line fix.

## Stage 3 — Gate

Per triage.md: the classified list in chat, then a single `AskUserQuestion` — write the report, and run the coverage check. Nothing is applied either way; the gate decides what gets produced, not what gets changed.

## Stage 4 — Coverage check (report-only)

Per mutation.md, unless the gate skipped it or the profile has no budget: mutate changed source lines, expect the affected tests to fail, restore each mutant before the next. Survivors are coverage gaps and become findings — this skill never writes the missing test.

## Stage 5 — Report & verdict

Per finalize.md: assert `HEAD` == `<HEAD0>`, nothing unstaged, nothing staged; write the report when the gate approved it; and reply in chat with the profile, a short summary, tier counts, the reminder that **nothing was changed**, and the verdict: **ready for PR** / **needs more work**.
