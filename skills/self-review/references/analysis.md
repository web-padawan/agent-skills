# Stage 1 — Breadth analysis

Everything in this stage is **read-only**. This skill never edits code; see the top rules in SKILL.md.

Stage 1 is one message: the profile's breadth agents (slop included), launched together so they share one barrier.

Every pass runs as a plugin agent (`agents/` at the plugin root). Each agent's definition carries its questions, category, output contract, and verification rules — the invoking prompt adds only run-specific facts: the context file path, the delivery clause, and whatever the pass table below names. **Fallback**, only when the plugin's agents are unavailable (this file copied out of the plugin): use `general-purpose` and paste the full body of the corresponding `agents/<name>.md` into the prompt.

## Delivery — how findings reach you

The launch rules, the delivery clause, the roll call, and the escalation ladder for lost reports live in `../../arch-review/references/delivery.md` (fallback `${CLAUDE_PLUGIN_ROOT}/skills/arch-review/references/delivery.md`) — read it before launching and follow it exactly. The one stage-specific note: stage 2 (triage) is a barrier — it needs every pass's findings before it starts — which is exactly why every agent runs with `run_in_background: false` and no `name`.

## Shared context file

Write it once before launching stage 1 (on a **fix**, before the premise check), next to the report as `<report-dir>/context.md`, and give every agent its path instead of repeating the content per prompt. It holds: branch name, the literal `<BASE>` and `<HEAD>` SHAs from stage 0 (with the note that the diff under review is `git diff <BASE>..<HEAD>`), `git diff --stat <BASE>..<HEAD>`, the changed file list, the detected change type and the signal that decided it, PR title/body when a PR exists, a summary of `$0` when given, the one-line intent, the severity rubric below, and the three sections that follow.

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

## Output contract — carried by the agent definitions

Every reviewer agent's definition carries the shared finding-line contract:

```
<category> | <file>:<line> | <A|B|C> | <claim>
```

One line per finding, at most **12** per agent, ranked most severe first, `NO FINDINGS` explicitly when clean — an empty reply is an error, re-run once. The prompt adds the delivery clause: the contract says what to report, the clause says where to put it, and an agent with only one of the two loses findings.

Categories: `general`, `scope`, `intent`, `requirements`, `premise`, `root-cause`, `behavior`, `integration`, `tests`, `slop` — plus `architecture`, `boundary`, `impact` and `api`, which only appear when `--deep` ran arch-review's lenses.

## Severity — A / B / C

Agents propose a tier; **stage-2 triage assigns the final one**. Agent-proposed tiers run high.

- **A — critical, must fix before merge.** Wrong behavior, regression, a test that lets a real bug through, a public API mistake that ships permanently, lint or test failure, a11y or security break, a convention violation a reviewer would block on.
- **B — should fix soon, a follow-up PR is fine.** Real but not merge-blocking: technical debt, coverage gaps away from the core behavior, naming or structure that will cost later, "this should be split" recommendations.
- **C — opinionated / taste.** Style, comment noise, member ordering, phrasing, micro-simplifications, subjective structure preferences.

Tie-breaker between A and B: **can a follow-up PR fix this without a breaking change or a user-visible bug?** No → A.

## The breadth passes

Passes are identified by name — the same names the profile table in SKILL.md uses, and the same ones the roll call and the report print. Each agent's definition holds its full contract; the **prompt adds** column is what the invoker must supply beyond the context file path and delivery clause.

| Pass | Agent | Profiles | Prompt adds |
| --- | --- | --- | --- |
| **general** | `agent-skills:general-reviewer` | all | On a **fix**: say the type is fix and name the repo's conventions doc — the definition then carries the folded scope/intent/integration questions, each finding under its own category |
| **scope** | `agent-skills:scope-reviewer` | feature, refactor | any type-signal disagreement recorded in stage 0 |
| **intent** | `agent-skills:intent-reviewer` | feature | — (reads the intent from the context file) |
| **integration** | `agent-skills:integration-reviewer` | feature, refactor, chore | — |
| **tests** | `agent-skills:test-reviewer` | all | — |
| **slop** | `agent-skills:comment-reviewer` | all | — |
| **requirements coverage** | `agent-skills:requirements-reviewer` | feature | the best requirements source, named |
| **root cause & blast radius** | `agent-skills:root-cause-reviewer` | fix | — |
| **premise & history** | `agent-skills:premise-reviewer` | fix, **before every other pass** | the behavior the fix changes; launch order and decision rules in `fix-profile.md` |
| **behavior preservation** | `agent-skills:behavior-reviewer` | refactor | — |

**Intent for the intent pass** — sources in priority order: `$0` parent PR/issue → PR body + linked issues → `.omc/plans/` files mentioning the branch topic → commit messages. Put the one-line intent and its source in the context file; if none exists, ask the user for one before launching.

## Retired passes

Passes retired as the pipeline evolved. Their questions did not go away — do not re-add the agents to this skill.

| Retired | Where its question lives now |
| --- | --- |
| **Architecture check** — which parts will be hard to modify in six months, and why | `arch-review`'s architectural lens (`Risk` + `Consequences` fields), asked per significant change — run `/agent-skills:arch-review` or pass `--deep` |
| **API design review** — judge new public surface as a consumer who lives with it for years | `arch-review`'s boundary lens (`Promise created` + `Why hard to change`, with `Consumers` naming who lives with it) |
| **Per-change deep review in this skill** (inventory + lens trio per significant change) | The whole machinery moved to `arch-review`; `--deep N` runs it from here, per SKILL.md's **Deep review** section |

Running branch-level copies of these alongside arch-review's lenses produces three phrasings of one finding and burns triage on dedup. If a whole-diff question genuinely has no per-change home — naming consistency *across* several new exports is the real example — raise it from the general or integration pass, not from a resurrected pass.
