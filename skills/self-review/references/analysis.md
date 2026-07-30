# Phases 1–2 — Analysis

Everything in these phases is **read-only**. No file changes before the phase-4 gate.

Launch only the agents the phase-0 profile names, plus the phase-2 passes, all in **one message**.

## Shared context file

Write it once before launching, next to the report as `<report-dir>/context.md`, and give every agent its path instead of repeating the content per prompt. It holds: branch name, the literal `<BASE>` SHA, `git diff --stat <BASE>..HEAD`, the changed file list, the detected change type and the signal that decided it, PR title/body when a PR exists, a summary of `$0` when given, the one-line intent, and the severity rubric below.

Each agent prompt is then: its own questions, its category, `read <report-dir>/context.md first`, and the output contract.

## Output contract — put it in every prompt

```
<category> | <file>:<line> | <A|B|C> | <claim>
```

- One line per finding, at most **12** findings, ranked most severe first.
- No code blocks, no quoted diffs, no restating the file — the claim is one sentence.
- `NO FINDINGS` explicitly when clean; an empty reply is an error, re-run once.

Categories: `general`, `architecture`, `scope`, `intent`, `api`, `requirements`, `root-cause`, `behavior`, `simplification`, `integration`, `tests`, `slop`.

## Severity — A / B / C

Agents propose a tier; **phase-3 triage assigns the final one**. Agent-proposed tiers run high.

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

Category `tests`. Coverage analysis is NOT this agent's job — phase 6 handles it.

### 6. Architecture check — `oh-my-claudecode:architect`

The question is cost of change, not correctness: **which parts of the new or changed logic will be hard to modify in six months, and why?**

- The 2–3 spots with the highest future cost of change, each with the reason it is sticky: public API surface that ships permanently, event or data-shape contracts, coupling across packages, state duplicated in places that will drift apart.
- Premature abstractions (a generalization with one caller) and missing ones (copy-paste that will fork).
- What a maintainer six months from now is most likely to misread.
- For each: the **smallest** change that lowers the future cost. No rewrites, no speculative extensibility.
- `NO FINDINGS` when the shape is fine. Expensive debt only, not a wish list.

Category `architecture`. In a component library a released public API cannot change without a breaking change, so API-shape debt is A; internal debt is normally B.

## Feature-only agents

A feature ships surface that cannot be taken back, so these two run in addition to the shared six.

### 7. API design review — `oh-my-claudecode:architect` (second instance), read-only

Judge the new public surface as a library consumer who will live with it for years. New or changed exports, properties, attributes, methods, events, slots, CSS custom properties, parts, and `.d.ts` entries:

- Naming and shape consistent with the same concept in sibling components — cite the sibling.
- Defaults: is the unconfigured behavior the one most consumers want, and does it match the existing default elsewhere?
- Is anything exposed that could stay private, or private that consumers will need? Public surface is the expensive kind.
- Breaking change smuggled in as an addition: changed default, narrowed accepted values, renamed part or event, altered event detail.
- Contract completeness: JSDoc with `@param`/`@return`, `@fires` for new events, types matching the runtime, documented `null`/`undefined` handling.
- a11y contract for new interactive surface: roles, `aria-*` wiring, focus order, keyboard operation.

Category `api`. Anything that would need a breaking change to correct is A.

### 8. Requirements coverage — `general-purpose`, read-only

Enumerate the feature's requirements from the best available source — `$0` parent issue/PR, the PR body, a `packages/*/spec/*.md` spec for the component, else the linked issue's acceptance criteria — then produce one finding per requirement that is **not** fully implemented **or** not covered by a test, and a `NO FINDINGS` line if all are.

Also flag: states the feature ignores that the component already supports (`disabled`, `readonly`, `required`, RTL, i18n/localized strings, theme variants, dark mode, keyboard-only use, screen reader), and interactions with existing features that no test exercises.

Category `requirements`. A stated requirement with no implementation is A; an implemented one with no test is A when it is the feature's core behavior, otherwise B.

## Fix-only agent

### 9. Root cause & blast radius — `oh-my-claudecode:debugger`, read-only

- **Root cause vs symptom**: name the actual cause, then say whether the diff fixes it or masks it (a guard added at the call site, a value coerced downstream, a timing workaround). A symptom fix is a finding even when the reported bug goes away.
- **Regression test**: is there a new test that fails without this diff? Name it, or report its absence — phase 6 verifies the claim.
- **Blast radius**: other places with the same pattern that still have the bug (sibling components, copy-pasted helper, the shared mixin the fix bypassed), and existing behavior that this fix changes for consumers who did not hit the bug.

Category `root-cause`. Symptom-only fix, missing regression test, and behavior changed for unaffected consumers are all A.

## Refactor-only agent

### 10. Behavior preservation — `general-purpose`, read-only

A refactor must not change what the code does.

- Any observable behavior difference: timing, event order, event count, property reflection, rendered DOM, error messages thrown.
- Changed or deleted assertions in existing tests — the strongest signal that behavior moved. Each one needs an equivalence argument, otherwise it is a finding.
- Public API touched at all (a refactor should not) and dropped edge-case handling that had no test.

Category `behavior`. Any unexplained observable change is A.

## Phase 2 — Quality passes, reviewer-only

Run each inside its own subagent, so their instructions stay out of the main context and their edits cannot reach the tree. Launch them in the phase-1 message.

- Subagent invoking `Skill(oh-my-claudecode:ai-slop-cleaner)` in its reviewer-only mode → `slop` findings, same output contract.
- Subagent invoking `Skill(simplify)` with an explicit "report findings only, do not edit any file" instruction → `simplification` findings. Skipped for the **chore** profile.

Then assert `git status --porcelain --untracked-files=no` is still empty. If a pass edited anyway: revert those tracked files with `git checkout -- <path>` (safe — the tree was clean at phase 0), delete files it created **by path**, and keep only its output as findings. Never `git clean`; never touch pre-existing untracked files.

## Comment policy — criteria for comment findings in `slop`

- Comments in code and tests are findings unless they are JSDoc or state a constraint the code cannot show (a browser-bug workaround with a link, a non-obvious ordering requirement).
- Comments that narrate what the next line does, restate the diff, or justify the change to a reviewer: always a finding.
- CSS files: any comment longer than 1 line, and decorative section banners.

Tier comment findings C, unless a comment is actively wrong about the code — that is B.
