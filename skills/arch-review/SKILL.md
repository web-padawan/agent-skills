---
name: arch-review
description: Deep-review a change through three lenses - architectural shape (observed behavior, risk, consequences), boundary/API promise (what it commits to, whose consumers, why hard to take back), and change-impact analysis (ripple effects, propagation paths, unblock conditions). Use when asked whether a change is architecturally safe, what a new API commits to, what a change's blast radius or impact is, or before making a breaking change. Takes a file, a diff range, a PR, or the current branch. Report-only, never edits. Not for a full pre-PR review with tests/scope/intent passes (self-review) or for posting PR comments (pr-review, adversarial-review).
argument-hint: "[<file>[:<lines>] | --diff <range> | <PR number or URL>] [--deep N]"
allowed-tools: Read, Grep, Glob, Task, Agent, AskUserQuestion, Bash(git:*), Bash(gh pr view:*), Bash(gh pr diff:*), Bash(*/scripts/get-pr-context.sh:*)
---

You are deep-reviewing one or more changes through three structured lenses. Everything is **read-only**: no edits, no commits, no staging, no posting. The output is a report in chat.

This skill is the plugin's only home of the per-change deep review — `self-review` runs no lenses of its own and delegates here when invoked with `--deep`. Invoked standalone, it answers pointed questions like "is this API safe to ship?" without the full pre-PR workflow around it.

| Reference | Covers |
| --- | --- |
| [`references/lenses.md`](references/lenses.md) | The lens agent table, severity mapping, rolling blocks into findings — field contracts live in the `agents/lens-*.md` definitions |
| [`references/significance.md`](references/significance.md) | What counts as a significant change, ranking, inventory contract |
| [`references/delivery.md`](references/delivery.md) | Launch rules, the delivery clause, roll call, escalation ladder — shared with self-review and pr-review |

References sit next to this file; if a relative read fails, use `${CLAUDE_PLUGIN_ROOT}/skills/arch-review/references/<name>.md`.

## 1 — Resolve the scope

- `<file>:<lines>` — one change: those lines as changed on the current branch (`git diff $(git merge-base origin/main HEAD)..HEAD -- <file>`); if the file is unchanged on the branch, review the code as it stands.
- `<file>` — same, the whole file's diff.
- `--diff <range>` — a git range, e.g. `--diff main..feature`.
- PR number or URL — run the shared context script (read-only): `${CLAUDE_PLUGIN_ROOT}/scripts/get-pr-context.sh --pr <number-or-url> --no-diff`, with the plugin root resolved to a literal path. Its `=== ANCHORS ===` section carries the literal merge-base and head SHAs (fetching `pull/<n>/head` when the PR is not checked out) plus the changed-file list — one call instead of separate `gh pr view` / `gh pr diff` plumbing, and the diff itself stays out of your context: the agents read it via the SHAs.
- No argument — the current branch's diff vs `git merge-base origin/main HEAD`.

Record the base and head SHAs as literals — shell variables do not persist between tool calls, and subagents never see them. If ANCHORS printed `error: cannot resolve merge base`, fall back to `git merge-base origin/<base-branch> HEAD` (base branch from PR metadata, else the repo's default branch) and record that SHA as the base.

**Write the shared context file.** Save the scope facts to `<scratchpad>/arch-review-context.md` — the script's output for a PR scope, the equivalent few lines for a file or range scope — and pass that **path** to every agent instead of restating the context inline. The lens and enumerator definitions already expect a context file. Without one you retype the same paragraph into every prompt, the wording drifts between them, and any correction reaches only the agents launched after you found it. When you discover something the context gets wrong, append it under an `## Orchestrator notes` heading (e.g. "the PR description is stale: it documents X, the code does Y") so every later agent reads the correction once, identically.

A single named change goes straight to step 3. Anything broader goes through the inventory first.

## 2 — Inventory (multi-change scopes only)

A multi-change run is not cheap: the inventory agent plus three lens agents per change is up to 13 agents at the default budget. When the user explicitly invoked the skill on that scope (slash command, "arch-review the branch"), proceed; when the skill fired on a passing question, confirm with one `AskUserQuestion` (header `Scope`) before spending the budget — offer the full run and a top-1-change run.

**Skip the inventory agent on small scopes.** When the scope touches one module and fewer than ~15 changed files, cluster the changes yourself from the ANCHORS file list per [`references/significance.md`](references/significance.md) and go straight to step 3. The inventory is a selection, not a review, and you can already see the whole file list — a separate agent earns its latency only on multi-module scopes where the ranking is genuinely unclear.

Otherwise run one `agent-skills:change-enumerator` inventory agent per [`references/significance.md`](references/significance.md) — the agent carries the rules and the output contract; the prompt adds the budget, the context file path, and the delivery clause. Budget: **4** clustered changes unless `--deep N` says otherwise. Everything below the line is listed in the report as `Not deep-reviewed`, never silently dropped.

Cluster before you count against the budget: several new files that exist only to serve one new public surface are **one** change, and a one-line `implements`/export addition belongs to the surface it adopts. Four files is often one trio, not four.

`NO SIGNIFICANT CHANGES` is a valid answer: report it and stop — no lens run on noise.

## 3 — Run the trio per change

Per [`references/lenses.md`](references/lenses.md): three separate agents per change — `agent-skills:lens-architectural`, `agent-skills:lens-boundary`, `agent-skills:lens-impact` — each handed exactly one change; the agents carry their own field contracts.

**Delivery** — follow [`references/delivery.md`](references/delivery.md) exactly: synchronous launch where the harness supports it, no `name`, the delivery clause verbatim in every prompt. Those decide whether the reports ever reach you.

**Batching**: cap each message at ~6 agents — trios for two changes per message, next batch only after the previous returns. A single overloaded message is where agents start returning surveys instead of reviews.

**While a batch is in flight**, pre-verify rather than poll — see delivery.md's waiting rule. Reading the changed files and checking the claims you expect (does that API actually exist, does the cited test actually cover that path, do sibling files really set that precedent) is triage work done early, and it is what lets you correct an overstated finding instead of forwarding it.

**Roll call**: after each batch, run delivery.md's roll call — tick every agent whose block you actually hold, escalate the ones that delivered nothing per its ladder, and mark any lens you had to run yourself `self-run`.

## 4 — Triage and report

1. Verify every finding line against the code — agents produce false positives. Unconfirmed → `accepted` with a one-line reason, kept in the report.
2. Dedup across the three lenses: lenses converging on one change is signal — merge the finding lines, mark `[3-lens]` / `[2-lens]`. Where a lens overstated a claim, say so in one clause and keep the corrected version; a lens whose framing you had to fix is more useful reported as corrected than as confirmed.
3. Assign the final tier: **A** — must fix before merge (wrong behavior, or a promise a follow-up could not walk back without a breaking change), **B** — real, follow-up is fine, **C** — taste. Tie-breaker: can a follow-up PR fix it without a breaking change or a user-visible bug? No → A.
4. Report **in chat**, per change in rank order. This skill's deliverable is the chat message: never publish an artifact, never write a report file, never post to the PR — those are other skills' jobs, and a second copy of the report is a liability, not a record.

   Scale the block prose to the finding, so the report stays readable at any budget:
   - **A-tier change** — its three blocks in full, close to verbatim.
   - **B/C-only change** — one condensed line per lens (`Risk` + `Suggestion`), because the finding lines already carry the claim.
   - **Clean change** — `NO FINDINGS` plus each lens's one-line summary, so the clean verdict is still on the record.

   Then the merged finding lines with tiers, `Not deep-reviewed` (every below-the-line candidate, with `covered by rank N` where that is the reason), and a closing tally (`A: n · B: n · C: n`, lenses `agent`/`self-run`). If the report would not fit a terminal read, cut block prose — never findings, never the tally.

Nothing was changed to produce the report; say so at the end.
