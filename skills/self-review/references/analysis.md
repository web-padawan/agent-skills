# Stages 1–2 — Inventory, breadth analysis, deep-review orchestration

Everything in these stages is **read-only**. This skill never edits code; see the top rules in SKILL.md.

Stage 1 is one fast agent whose output is the deep review's work list. Stage 2a launches the profile's breadth agents plus the slop pass — in the same message as stage 2b (batching below), so both halves share one barrier.

Every pass runs as a plugin agent (`agents/` at the plugin root). Each agent's definition carries its questions, category, output contract, and verification rules — the invoking prompt adds only run-specific facts: the context file path, the delivery clause, and whatever the pass table below names. **Fallback**, only when the plugin's agents are unavailable (this file copied out of the plugin): use `general-purpose` and paste the full body of the corresponding `agents/<name>.md` into the prompt.

## Delivery — how findings reach you

A pass that never reports is worse than a pass you skipped: it looks done. Two launch choices decide whether findings arrive, and the **defaults lose them**:

- **Pass `run_in_background: false` on every agent in these stages.** Stage 3 is a barrier — you need all findings before triage — so a synchronous run is what you actually want, and it makes each agent's report arrive as its tool result. Background agents report through a separate notification channel, and that is where reports vanish.
- **Do not pass `name`.** A named agent becomes an addressable teammate: it ends its turn *idle and still alive*, and its final text is never returned to you. Name an agent only when you genuinely need to message it mid-run.

Then, whatever the mechanism, put this clause in every agent prompt so a second channel exists:

```
Your findings are the deliverable. Return them as the CONTENT of your final message.
If you have a SendMessage tool, ALSO send them to `main` in the same format.
Do not write them to a file, and do not end your turn without them.
```

**Recognize a lost report.** A message like `{"type":"idle_notification","idleReason":"available"}`, or a completion carrying no findings, is a **delivery failure** — not a clean pass. Never record it as `NO FINDINGS`.

## Shared context file

Write it once before launching stage 1 (on a **fix**, before the premise check), next to the report as `<report-dir>/context.md`, and give every agent its path instead of repeating the content per prompt. It holds: branch name, the literal `<BASE>` SHA, `git diff --stat <BASE>..HEAD`, the changed file list, the detected change type and the signal that decided it, PR title/body when a PR exists, a summary of `$0` when given, the one-line intent, the severity rubric below, and the three sections that follow.

**Append the significant-change inventory to it when stage 1 returns**, before launching stage 2. Every stage-2 agent then reads the same ranked list, and the deep-review agents get their target from the same file as everyone else instead of having it restated per prompt.

Each agent prompt is then: `read <report-dir>/context.md first`, the run-specific facts from the pass table below, and the delivery clause — questions, categories, and output contracts live in the agent definitions.

### Conventions docs

Name the repo's conventions sources, in priority order, with paths — the canonical conventions file, the guideline chapters that cover what this diff touches, and any topic-specific rules doc that governs the change (a signals/bindings rules file for a change to `bind*` methods, for example). Agents that have to find these themselves spend tool calls doing it, and each one finds a different subset.

### Settled facts

Facts you verified in stage 0, plus the citations the premise pass returns on a **fix**. Each entry is a one-line claim with its evidence — `file:line`, a SHA, an issue number, or the command that produced it.

Head the section with this instruction, verbatim:

> Each entry is authoritative. Do not open the file it came from. If a finding of yours depends on an entry being wrong, report that as a finding with your reasoning — one line, no re-investigation.

Do **not** invite agents to re-check the ledger. Measured on a real fix branch, a ledger headed "do not re-derive, *do challenge*" was re-derived from source by three of four agents: the invitation is what licenses the spend, and the sceptical reading of a settled fact costs as much as establishing it.

### Open leads

Suspicions worth chasing that you deliberately have not resolved. **Every lead names exactly one owner pass**:

```
- [owner: tests] The append branch is never exercised with an already-added component.
- [owner: root cause] `removeAll()` may still bypass the guard the fix restored.
```

Other passes do not investigate a lead they do not own; triage inherits the owner's verdict. An unowned lead is chased once per agent — on the same measured branch, three unowned leads handed to four agents produced four independent verifications of one non-issue, the single largest waste in the run. If a lead matters enough to want two verdicts, say so on the lead and name both owners.

## Stage 1 — Change inventory

One `agent-skills:change-enumerator` agent, read-only. Its definition ([`../../agents/change-enumerator.md`](../../agents/change-enumerator.md)) carries the five significance rules, the exclusion list, and the inventory contract — including the `BELOW LINE` list that stage 6 prints under `## Not deep-reviewed`, and `NO SIGNIFICANT CHANGES` as the valid empty answer that skips stage 2b. The prompt adds the context file path, the profile's deep-review budget, and the delivery clause.

## Stage 2b — Deep review: batching & prompt shape

The three lens agents — `agent-skills:lens-architectural`, `agent-skills:lens-boundary`, `agent-skills:lens-impact` — carry their field contracts and finding-line contracts in their definitions. Read `../../arch-review/references/lenses.md` (fallback `${CLAUDE_PLUGIN_ROOT}/skills/arch-review/references/lenses.md`) before launching — it holds the severity mapping and block→finding rules that stage 3 and stage 6 apply. What follows is only the launch mechanics.

**Batching.** 3 agents per change plus the breadth passes adds up fast: even a refactor at budget 4 is 12 deep agents on top of 6 breadth agents. Cap each message at roughly **6 agents**:

- Message 1 — the breadth passes.
- Message 2 — the trios for the top 2 ranked changes.
- Message 3 onward — two more changes per message until the budget is spent.

On a **fix** there are no trios and no second message: **four agents in one** — the general,
tests and root-cause passes plus the single lens on the fix's own hunks. The premise pass has
already run before Stage 1 and cleared the premise (launch order in `fix-profile.md`).

Do not put every trio in the stage-2 message with the breadth passes. Measured on a real refactor branch, an 18-agent single message is where deep agents start returning surveys instead of reviews, and one lost report costs a whole lens on a change. Three or four messages of six cost some wall-clock and buy every agent a full run. The batch boundary is a launch detail, not a barrier for triage — stage 3 still waits for everything before verifying anything.

**Prompt shape — shared by all three lenses.** Every prompt carries:

- `read <report-dir>/context.md first` — it holds the branch, the literal `<BASE>` SHA, the change type, and the ranked inventory.
- The one change this agent reviews: its rank, `file:line-range`, and the inventory's one-sentence description. **One change per agent** — an agent handed the whole list writes a survey instead of a review.
- The delivery clause from the **Delivery** section above. That clause is not optional; a prompt without it loses its report.
- `run_in_background: false`, no `name`.

## Output contract — carried by the agent definitions

Every reviewer agent's definition carries the shared finding-line contract:

```
<category> | <file>:<line> | <A|B|C> | <claim>
```

One line per finding, at most **12** per agent, ranked most severe first, `NO FINDINGS` explicitly when clean — an empty reply is an error, re-run once. The prompt adds the delivery clause: the contract says what to report, the clause says where to put it, and an agent with only one of the two loses findings.

Categories: `general`, `architecture`, `boundary`, `impact`, `scope`, `intent`, `api`, `requirements`, `premise`, `root-cause`, `behavior`, `integration`, `tests`, `slop`.

`architecture`, `boundary` and `impact` come from the deep review, which also emits `api` when the boundary in question is public API. The rest come from the breadth passes below.

## Severity — A / B / C

Agents propose a tier; **stage-3 triage assigns the final one**. Agent-proposed tiers run high.

- **A — critical, must fix before merge.** Wrong behavior, regression, a test that lets a real bug through, a public API mistake that ships permanently, lint or test failure, a11y or security break, a convention violation a reviewer would block on.
- **B — should fix soon, a follow-up PR is fine.** Real but not merge-blocking: technical debt, coverage gaps away from the core behavior, naming or structure that will cost later, "this should be split" recommendations.
- **C — opinionated / taste.** Style, comment noise, member ordering, phrasing, micro-simplifications, subjective structure preferences.

Tie-breaker between A and B: **can a follow-up PR fix this without a breaking change or a user-visible bug?** No → A.

## The breadth passes

Passes are identified by name — the same names the profile table in SKILL.md uses, and the same ones the roll call and the report print. Each agent's definition holds its full contract; the **prompt adds** column is what the invoker must supply beyond the context file path and delivery clause.

| Pass | Agent | Profiles | Prompt adds |
| --- | --- | --- | --- |
| **general** | `agent-skills:general-reviewer` | all | On a **fix**: say the type is fix and name the repo's conventions doc — the definition then carries the folded scope/intent/integration/slop questions, each finding under its own category |
| **scope** | `agent-skills:scope-reviewer` | feature, refactor | any type-signal disagreement recorded in stage 0 |
| **intent** | `agent-skills:intent-reviewer` | feature | — (reads the intent from the context file) |
| **integration** | `agent-skills:integration-reviewer` | feature, refactor, chore | — |
| **tests** | `agent-skills:test-reviewer` | all | — |
| **requirements coverage** | `agent-skills:requirements-reviewer` | feature | the best requirements source, named |
| **root cause & blast radius** | `agent-skills:root-cause-reviewer` | fix | — |
| **behavior preservation** | `agent-skills:behavior-reviewer` | refactor | — |
| **premise & history** | `agent-skills:premise-reviewer` | fix, **before every other pass** | the behavior the fix changes; launch order and decision rules in `fix-profile.md` |

**Intent for the intent pass** — sources in priority order: `$0` parent PR/issue → PR body + linked issues → `.omc/plans/` files mentioning the branch topic → commit messages. Put the one-line intent and its source in the context file; if none exists, ask the user for one before launching.

## Retired passes

Two branch-level agents were removed when the per-change deep review took over. Their questions did not go away — do not re-add the agents.

| Retired | Where its question lives now |
| --- | --- |
| **Architecture check** — which parts will be hard to modify in six months, and why | The architectural review's `Risk` + `Consequences` fields, asked per significant change instead of per branch |
| **API design review** — judge new public surface as a consumer who lives with it for years | The boundary review's `Promise created` + `Why hard to change` fields, with `Consumers` naming who lives with it |

Running them alongside the trio produces three phrasings of one finding and burns triage on dedup. If a whole-diff question genuinely has no per-change home — naming consistency *across* several new exports is the real example — raise it from the general or integration pass, not from a resurrected pass.

## Stage 2a — Slop pass

Runs for every type except **fix**, whose five-agent cap folds the comment policy into the general pass.

Launch `agent-skills:comment-reviewer` in the stage-2 message — its definition carries the comment policy and the comment-accuracy checks, and it cannot edit.

Then assert `git status --porcelain --untracked-files=no` is still empty. If any pass edited anyway: revert those tracked files with `git checkout -- <path>` (safe — the tree was clean at stage 0), delete files it created **by path**, and keep only its output as findings. Never `git clean`; never touch pre-existing untracked files.

This skill has no apply stage, so a modified tracked file at this point is never something to keep — revert first, ask questions after.

## Delivery check — run before triage

Roll call: list every agent you launched — stage 1's enumerator, the breadth passes, the slop pass, and all three lenses of every deep-reviewed change — and tick the ones whose findings you actually hold.

**Print it by pass name, one per line, with the finding count.** Never by number: a line like `11 ✅ · 5 ✅ · boundary ✅` mixes two identifier systems and tells the reader nothing about what was checked.

```
Delivery roll call
  premise & history   ✅ agent · no findings · premise: sound
  general             ✅ agent · 8 findings
  tests               ✅ agent · 8 findings
  root cause          ✅ agent · 6 findings (1 proposed A)
  boundary lens       ✅ agent · 3 findings + narrative block
```

Markers: `✅ agent` · `⚠️ self-run` · `❌ missing` · `⏳ running`. The finding count makes the roll call double as a yield tally, which is what tells you later whether a pass earns its place in the profile. Use the same names in any mid-run status line — `Done: premise & history, general, tests. Waiting on: root cause, boundary lens.` — so the reader never has to map a digit to a purpose.

For each pass that delivered nothing, escalate the **mechanism** — a retry down the same channel fails identically, so never just re-send the same call:

1. **Ping once**, only if the agent is named and still alive: restate the output contract, name the 2–3 questions you most need answered, and include the facts you have already verified so it does not spend its run re-deriving them.
2. **Re-spawn once** with `run_in_background: false` and no `name` — a different channel, not a second try down the broken one.
3. **Self-run the pass**: read the files and answer that pass's questions yourself (the questions are in the pass's `agents/<name>.md` definition). Tag every finding it yields `self-run`.

Never drop a pass silently, and never let a lost report pass for a clean one. Carry each pass's status — `agent`, `self-run`, or `missing` — into stage 6.

Treat a self-run pass as **weaker evidence** than an agent pass: you are reviewing with the same context that produced the diff, which makes you the reader least likely to notice what it takes for granted. Say which passes were self-run at the gate, rather than presenting them as independent confirmation.
