---
name: arch-review
description: Deep-review a change through three lenses - architectural shape (observed behavior, risk, consequences), boundary/API promise (what it commits to, whose consumers, why hard to take back), and change-impact analysis (ripple effects, propagation paths, unblock conditions). Use when asked whether a change is architecturally safe, what a new API commits to, what a change's blast radius or impact is, or before making a breaking change. Takes a file, a diff range, a PR, or the current branch. Report-only, never edits. Not for a full pre-PR review with tests/framing/conformance passes (self-review) or for posting PR comments (pr-review, adversarial-review).
argument-hint: "[<file>[:<lines>] | --diff <range> | <PR number or URL>] [--deep N]"
allowed-tools: Read, Grep, Glob, Task, Agent, AskUserQuestion, Bash(git:*), Bash(gh pr view:*), Bash(gh pr diff:*), Bash(*/scripts/get-pr-context.sh:*), Bash(*/scripts/review-plan.sh:*)
---

You are deep-reviewing one or more changes through three structured lenses. Everything is
**read-only**: no edits, no commits, no staging, no posting. The output is a report in chat.

This skill is the plugin's only home of the per-change deep review — `self-review` runs no
lenses of its own and delegates here when invoked with `--deep`. Invoked standalone, it
answers pointed questions like "is this API safe to ship?" without the full pre-PR workflow.

| Reference | Covers |
| --- | --- |
| [`../../references/pipeline.md`](../../references/pipeline.md) | The shared pipeline: context file, fan-out, roll call, triage |
| [`../../references/severity.md`](../../references/severity.md) | A / B / C, the tie-breaker, the lens severity mapping |
| [`../../references/delivery.md`](../../references/delivery.md) | Launch rules, the delivery clause, roll call, escalation ladder |
| [`references/lenses.md`](references/lenses.md) | The lens agent table and how blocks roll into findings |
| [`references/significance.md`](references/significance.md) | What counts as a significant change, ranking, inventory contract |

Relative paths resolve from this file; on a failed read use
`${CLAUDE_PLUGIN_ROOT}/references/<name>.md` or
`${CLAUDE_PLUGIN_ROOT}/skills/arch-review/references/<name>.md`.

## 1 — Resolve the scope, write the context file

- `<file>:<lines>` — one change: those lines as changed on the current branch
  (`git diff $(git merge-base origin/main HEAD)..HEAD -- <file>`); if the file is unchanged on
  the branch, review the code as it stands.
- `<file>` — same, the whole file's diff.
- `--diff <range>` — a git range, e.g. `--diff main..feature`.
- A PR number or URL, or no argument (the current branch) — run the plan script once, with the
  plugin root as a literal path:
  `${CLAUDE_PLUGIN_ROOT}/scripts/review-plan.sh --mode arch [--pr <number-or-url>] [--deep N]`.
  It prints the PR context plus a `=== PLAN ===` block with the literal `base`/`head` SHAs and
  the changed-file list; the diff itself stays out of your context — the agents read it via
  the SHAs. Arch mode runs no breadth passes: the lens trio below is the whole review.

Record the SHAs as literals — shell variables do not persist between tool calls, and subagents
never see them.

Then write the shared context file per [`../../references/pipeline.md`](../../references/pipeline.md)
§2 (for a file or range scope, the equivalent few lines), and pass that **path** to every
agent instead of restating the context inline.

A single named change goes straight to step 3. Anything broader goes through the inventory.

## 2 — Inventory (multi-change scopes only)

A multi-change run is not cheap: the inventory agent plus three lens agents per change is up to
13 agents at the default budget. When the user explicitly invoked the skill on that scope
(slash command, "arch-review the branch"), proceed; when the skill fired on a passing question,
confirm with one `AskUserQuestion` (header `Scope`) first — offer the full run and a
top-1-change run. `self-review --deep N` is already that confirmation; skip the question.

**Skip the inventory agent on small scopes.** When the scope touches one module and fewer than
~15 changed files, cluster the changes yourself per
[`references/significance.md`](references/significance.md) and go straight to step 3. The
inventory is a selection, not a review, and it earns its latency only on multi-module scopes
where the ranking is genuinely unclear.

Otherwise run one `agent-skills:change-enumerator` per that file — the agent carries the rules
and the output contract; the prompt adds the budget, the context file path, and the delivery
clause. Budget: **4** clustered changes unless `--deep N` says otherwise. Everything below the
line is listed in the report as `Not deep-reviewed`, never silently dropped.
`NO SIGNIFICANT CHANGES` is a valid answer: report it and stop.

## 3 — Run the trio per change

Per [`references/lenses.md`](references/lenses.md): three separate agents per change —
`agent-skills:lens-architectural`, `agent-skills:lens-boundary`, `agent-skills:lens-impact` —
each handed exactly **one** change. The agents carry their own field contracts.

Delivery, waiting and roll call per [`../../references/delivery.md`](../../references/delivery.md),
exactly. One addition it does not cover: **cap each message at ~6 agents** — trios for two
changes per message, the next batch only after the previous returns. A single overloaded message
is where agents start returning surveys instead of reviews.

## 4 — Triage and report

Triage per [`../../references/pipeline.md`](../../references/pipeline.md) §5, tiers per
[`../../references/severity.md`](../../references/severity.md). Then report **in chat**, per
change in rank order. This skill's deliverable is the chat message: never publish an artifact,
never write a report file, never post to the PR — a second copy of the report is a liability,
not a record.

Scale the block prose to the finding, so the report stays readable at any budget:

- **A-tier change** — its three blocks in full, close to verbatim.
- **B/C-only change** — one condensed line per lens (`Risk` + `Suggestion`); the finding lines
  already carry the claim.
- **Clean change** — `NO FINDINGS` plus each lens's one-line summary, so the clean verdict is
  on the record.

Then the merged finding lines with tiers, `Not deep-reviewed` (every below-the-line candidate,
with `covered by rank N` where that is the reason), and a closing tally (`A: n · B: n · C: n`,
lenses `agent`/`self-run`). If the report would not fit a terminal read, cut block prose —
never findings, never the tally.

Nothing was changed to produce the report; say so at the end.
