# Stages 1–2a — Inventory & breadth analysis

Everything in these stages is **read-only**. This skill never edits code; see the top rules in SKILL.md.

Stage 1 is one fast agent whose output is the deep review's work list. Stage 2a launches the profile's breadth agents plus the slop pass — in the same message as stage 2b (deep-review.md), so both halves share one barrier.

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

Write it once before launching stage 1, next to the report as `<report-dir>/context.md`, and give every agent its path instead of repeating the content per prompt. It holds: branch name, the literal `<BASE>` SHA, `git diff --stat <BASE>..HEAD`, the changed file list, the detected change type and the signal that decided it, PR title/body when a PR exists, a summary of `$0` when given, the one-line intent, and the severity rubric below.

**Append the significant-change inventory to it when stage 1 returns**, before launching stage 2. Every stage-2 agent then reads the same ranked list, and the deep-review agents get their target from the same file as everyone else instead of having it restated per prompt.

Each agent prompt is then: its own questions, its category, `read <report-dir>/context.md first`, and the output contract.

## Stage 1 — Change inventory

One `general-purpose` agent, read-only. Its prompt carries the five significance rules and the exclusion list from SKILL.md verbatim, the profile's deep-review budget, and this contract:

```
<rank> | <file>:<line-range> | <rule 1-5> | <one sentence: what it changes>
```

- Ranked most significant first, by public-surface reach, then cross-module reach, then logic density.
- Exactly the budget's worth of lines, then a `BELOW LINE` header, then every remaining candidate in the same format with the reason it ranked lower. The below-line list is what stage 6 prints under `## Not deep-reviewed`; an agent that omits it has not finished.
- `NO SIGNIFICANT CHANGES` when the diff is entirely non-significant — a valid answer, and stage 2b is then skipped.
- Add the delivery clause above.

The inventory is a *selection*, not a review: no severities, no findings, no recommendations. Keeping it cheap is what makes the extra barrier worth its latency.

## Output contract — put it in every stage-2a prompt

```
<category> | <file>:<line> | <A|B|C> | <claim>
```

- One line per finding, at most **12** findings, ranked most severe first.
- No code blocks, no quoted diffs, no restating the file — the claim is one sentence.
- `NO FINDINGS` explicitly when clean; an empty reply is an error, re-run once.
- Add the delivery clause from **Delivery** above — the contract says what to report, that clause says where to put it, and a prompt with only one of the two loses findings.

Categories: `general`, `architecture`, `boundary`, `impact`, `scope`, `intent`, `api`, `requirements`, `root-cause`, `behavior`, `integration`, `tests`, `slop`.

`architecture`, `boundary` and `impact` come from the deep review (deep-review.md), which also emits `api` when the boundary in question is public API. The rest come from the breadth agents below.

## Severity — A / B / C

Agents propose a tier; **stage-3 triage assigns the final one**. Agent-proposed tiers run high.

- **A — critical, must fix before merge.** Wrong behavior, regression, a test that lets a real bug through, a public API mistake that ships permanently, lint or test failure, a11y or security break, a convention violation a reviewer would block on.
- **B — should fix soon, a follow-up PR is fine.** Real but not merge-blocking: technical debt, coverage gaps away from the core behavior, naming or structure that will cost later, "this should be split" recommendations.
- **C — opinionated / taste.** Style, comment noise, member ordering, phrasing, micro-simplifications, subjective structure preferences.

Tie-breaker between A and B: **can a follow-up PR fix this without a breaking change or a user-visible bug?** No → A.

## Shared agents

### 1. General review — `oh-my-claudecode:code-reviewer`

Review the full branch diff (`git diff <BASE>..HEAD`, literal SHA) for correctness, logic defects, edge cases, and API-contract problems. Category `general`.

### 2. Scope check — `general-purpose`, read-only

- Can this branch be split into meaningful independent parts? Name the split if so.
- Are files/hunks touched that are not needed for the stated goal (drive-by changes)?
- With a parent PR/issue: does this extraction stand alone, and what of the parent does it silently depend on?
- Does the diff match its declared change type, or is a "fix" really a feature?

Category `scope`. A split recommendation is a judgment call for the user, so tier it B at most — never A. When the profile skips this agent (**fix**, **chore**), fold the drive-by question into agent 1's prompt.

### 3. Intent check — `general-purpose`, read-only

Intent sources, in priority order: `$0` parent PR/issue → PR body + linked issues → `.omc/plans/` files mentioning the branch topic → commit messages. If none exists, ask the user for a one-line intent before launching.

- Does the implemented approach match the stated intent, or has it drifted?
- **Plausible-nonsense hunt**: tests that pass while pinning wrong behavior — assertions encoding what the code *does* rather than what the intent *requires*. Compare each new test's expectation against the intent, not the implementation.

Category `intent`.

### 4. Integration check — `general-purpose`, read-only

Must read the repo's conventions doc in full first — `CONVENTIONS.md` at the repo root (that is the one in vaadin/web-components), else the conventions part of `CLAUDE.md` / `AGENTS.md`, else the dominant patterns of the touched packages — then check the diff for:

- Convention violations (cite the convention).
- Naming consistent with sibling components/mixins for the same concept.
- Method and property ordering matching the surrounding file and analogous files in other packages.

Category `integration`.

### 5. Test review — `oh-my-claudecode:test-engineer`

Review tests changed/added on this branch:

- Each assertion validates observable expected behavior, not incidental output.
- No reaching into implementation details or private APIs (`_underscore` members, internal DOM structure outside the contract) unless no public path exists.
- Setup/teardown sound; no order dependence.

Category `tests`. Coverage analysis is NOT this agent's job — stage 5 handles it.

## Retired passes

Two branch-level agents were removed when the per-change deep review took over. Their questions did not go away — do not re-add the agents.

| Retired | Where its question lives now |
| --- | --- |
| **6. Architecture check** — which parts will be hard to modify in six months, and why | The architectural review's `Risk` + `Consequences` fields, asked per significant change instead of per branch |
| **7. API design review** — judge new public surface as a consumer who lives with it for years | The boundary review's `Promise created` + `Why hard to change` fields, with `Consumers` naming who lives with it |

Running them alongside the trio produces three phrasings of one finding and burns triage on dedup. If a whole-diff question genuinely has no per-change home — naming consistency *across* several new exports is the real example — raise it from agent 1 or agent 4, not from a resurrected pass.

## Feature-only agent

### 8. Requirements coverage — `general-purpose`, read-only

Enumerate the feature's requirements from the best available source — `$0` parent issue/PR, the PR body, a `packages/*/spec/*.md` spec for the component, else the linked issue's acceptance criteria — then produce one finding per requirement that is **not** fully implemented **or** not covered by a test, and a `NO FINDINGS` line if all are.

Also flag: states the feature ignores that the component already supports (`disabled`, `readonly`, `required`, RTL, i18n/localized strings, theme variants, dark mode, keyboard-only use, screen reader), and interactions with existing features that no test exercises.

Category `requirements`. A stated requirement with no implementation is A; an implemented one with no test is A when it is the feature's core behavior, otherwise B.

## Fix-only agent

### 9. Root cause & blast radius — `oh-my-claudecode:debugger`, read-only

- **Root cause vs symptom**: name the actual cause, then say whether the diff fixes it or masks it (a guard added at the call site, a value coerced downstream, a timing workaround). A symptom fix is a finding even when the reported bug goes away.
- **Regression test**: is there a new test that fails without this diff? Name it, or report its absence — stage 5 verifies the claim.
- **Blast radius**: other places with the same pattern that still have the bug (sibling components, copy-pasted helper, the shared mixin the fix bypassed), and existing behavior that this fix changes for consumers who did not hit the bug.

Category `root-cause`. Symptom-only fix, missing regression test, and behavior changed for unaffected consumers are all A.

## Refactor-only agent

### 10. Behavior preservation — `general-purpose`, read-only

A refactor must not change what the code does.

- Any observable behavior difference: timing, event order, event count, property reflection, rendered DOM, error messages thrown.
- Changed or deleted assertions in existing tests — the strongest signal that behavior moved. Each one needs an equivalence argument, otherwise it is a finding.
- Public API touched at all (a refactor should not) and dropped edge-case handling that had no test.

Category `behavior`. Any unexplained observable change is A.

## Stage 2a — Slop pass, reviewer-only

Run it inside its own subagent, so its instructions stay out of the main context and its edits cannot reach the tree. Launch it in the stage-2 message.

- Subagent invoking `Skill(oh-my-claudecode:ai-slop-cleaner)` in its reviewer-only mode → `slop` findings, same output contract.

Then assert `git status --porcelain --untracked-files=no` is still empty. If the pass edited anyway: revert those tracked files with `git checkout -- <path>` (safe — the tree was clean at stage 0), delete files it created **by path**, and keep only its output as findings. Never `git clean`; never touch pre-existing untracked files.

This skill has no apply stage, so a modified tracked file at this point is never something to keep — revert first, ask questions after.

## Delivery check — run before triage

Roll call: list every agent you launched — stage 1's enumerator, the breadth agents, the slop pass, and all three lenses of every deep-reviewed change — and tick the ones whose findings you actually hold. For each that delivered nothing, escalate the **mechanism** — a retry down the same channel fails identically, so never just re-send the same call:

1. **Ping once**, only if the agent is named and still alive: restate the output contract, name the 2–3 questions you most need answered, and include the facts you have already verified so it does not spend its run re-deriving them.
2. **Re-spawn once** with `run_in_background: false` and no `name` — a different channel, not a second try down the broken one.
3. **Self-run the pass**: read the files and answer that pass's questions yourself. Tag every finding it yields `self-run`.

Never drop a pass silently, and never let a lost report pass for a clean one. Carry each pass's status — `agent`, `self-run`, or `missing` — into stage 6.

Treat a self-run pass as **weaker evidence** than an agent pass: you are reviewing with the same context that produced the diff, which makes you the reader least likely to notice what it takes for granted. Say which passes were self-run at the gate, rather than presenting them as independent confirmation.

## Comment policy — criteria for comment findings in `slop`

- Comments in code and tests are findings unless they are JSDoc or state a constraint the code cannot show (a browser-bug workaround with a link, a non-obvious ordering requirement).
- Comments that narrate what the next line does, restate the diff, or justify the change to a reviewer: always a finding.
- CSS files: any comment longer than 1 line, and decorative section banners.

Tier comment findings C, unless a comment is actively wrong about the code — that is B.
