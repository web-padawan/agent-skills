# Phases 1–2 — Analysis

Everything in these phases is **read-only**. No file changes before the phase-4 gate.

## Finding format

Every agent returns findings as one line each:

```
<category> | <file>:<line> | <A|B|C> | <claim>
```

Categories: `general`, `architecture`, `scope`, `direction`, `simplification`, `integration`, `tests`, `slop`. Agents must return `NO FINDINGS` explicitly when clean — an empty reply is an error, re-run once.

Give every agent the same context block: branch name, the literal `<BASE>` SHA from phase 0, changed file list, PR title/body (when present), parent PR/issue summary (when `$0` given), and the severity rubric below.

## Severity — A / B / C

Agents propose a tier; **phase-3 triage assigns the final one**. Agent-proposed tiers run high.

- **A — critical, must fix before merge.** Wrong behavior, regression, a test that lets a real bug through, a public API mistake that ships permanently, lint or test failure, a11y or security break, a convention violation a reviewer would block on.
- **B — should fix soon, a follow-up PR is fine.** Real but not merge-blocking: technical debt, coverage gaps away from the core behavior, naming or structure that will cost later, "this should be split" recommendations.
- **C — opinionated / taste.** Style, comment noise, member ordering, phrasing, micro-simplifications, subjective structure preferences.

Tie-breaker between A and B: **can a follow-up PR fix this without a breaking change or a user-visible bug?** No → A.

## Phase 1 agents — launch every applicable one in a single message

### 1. General review — `oh-my-claudecode:code-reviewer`

Prompt: review the full branch diff (`git diff <BASE>..HEAD`, literal SHA) for correctness, logic defects, edge cases, and API-contract problems. Category `general`.

### 2. Scope check — `general-purpose`, read-only

Prompt must ask:
- Can this branch be split into meaningful independent parts? Name the split if so.
- Are files/hunks touched that are not needed for the stated goal (drive-by changes)?
- When a parent PR/issue is given: does this extraction stand alone, and what of the parent does it silently depend on?
Category `scope`. A split recommendation is a judgment call for the user, so tier it B at most — never A.

### 3. Direction check — `general-purpose`, read-only

Original-idea sources, in priority order: `$0` parent PR/issue → PR body + linked issues → `.omc/plans/` files mentioning the branch topic → commit messages on the branch. If none exists, ask the user for a one-line intent before launching this agent.

Prompt must ask:
- Does the implemented approach match the original idea, or has it drifted?
- **Plausible-nonsense hunt**: find tests that pass while pinning wrong behavior — assertions that encode what the code *does* rather than what the idea *requires*. Compare each new test's expectation against the stated intent, not against the implementation.
Category `direction`.

### 4. Integration check — `general-purpose`, read-only

Prompt must require reading the repo's conventions doc in full first — `CONVENTIONS.md` at the repo root (that is the one in vaadin/web-components), else the conventions part of `CLAUDE.md` / `AGENTS.md`, else the dominant patterns of the touched packages — then check the diff for:
- Convention violations (cite the convention).
- Naming consistent with sibling components/mixins for the same concept.
- Method and property ordering matching the surrounding file and analogous files in other packages.
Category `integration`.

### 5. Test review — `oh-my-claudecode:test-engineer`

Prompt: review tests changed/added on this branch. Check that:
- Each assertion validates observable expected behavior, not incidental output.
- Tests do not reach into implementation details or private APIs (`_underscore` members, internal DOM structure that is not part of the contract) unless no public path exists.
- Setup/teardown is sound; no order dependence.
Category `tests`. Coverage analysis is NOT this agent's job — phase 6 handles it.

### 6. Architecture check — `oh-my-claudecode:architect`, only when phase 0 turned it on

The question is cost of change, not correctness: **which parts of the new or changed logic will be hard to modify in six months, and why?**

Prompt must ask for:
- The 2–3 spots with the highest future cost of change, each with the reason it is sticky: public API surface that ships permanently, event or data-shape contracts, coupling across packages, state duplicated in places that will drift apart.
- Premature abstractions (a generalization with one caller) and missing ones (copy-paste that will fork).
- What a maintainer six months from now is most likely to misread.
- For each: the **smallest** change that lowers the future cost. No rewrites, no speculative extensibility.
- `NO FINDINGS` when the shape is fine. Expensive debt only, not a wish list.

Category `architecture`. In a component library a released public API cannot change without a breaking change, so API-shape debt is A; internal debt is normally B.

## Phase 2 — Quality passes, reviewer-only

Both run **without editing**:

- `Skill(oh-my-claudecode:ai-slop-cleaner)` in its reviewer-only mode → `slop` findings.
- `Skill(simplify)` with an explicit "report findings only, do not edit any file" instruction → `simplification` findings.

Then assert `git status --porcelain --untracked-files=no` is still empty. If a pass edited anyway: revert those tracked files with `git checkout -- <path>` (safe — the tree was clean at phase 0), delete files it created **by path**, and keep only its output as findings. Never `git clean`; never touch pre-existing untracked files.

## Comment policy — criteria for comment findings in `slop`

- Comments in code and tests are findings unless they are JSDoc or state a constraint the code cannot show (a browser-bug workaround with a link, a non-obvious ordering requirement).
- Comments that narrate what the next line does, restate the diff, or justify the change to a reviewer: always a finding.
- CSS files: any comment longer than 1 line, and decorative section banners.

Tier comment findings C, unless a comment is actively wrong about the code — that is B.
