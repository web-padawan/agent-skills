# Phases 1–2 — Analysis agents

## Finding format

Every agent returns findings as one line each:

```
<category> | <file>:<line> | <severity: high|medium|low> | <claim>
```

Categories: `general`, `scope`, `direction`, `simplification`, `integration`, `tests`, `slop`. Agents must return `NO FINDINGS` explicitly when clean — an empty reply is an error, re-run once.

Give every agent the same context block: branch name, the literal `<BASE>` SHA from phase 0, changed file list, PR title/body (when present), parent PR/issue summary (when `$0` given).

## Phase 1 agents (launch all four in one message)

### 1. General review — `oh-my-claudecode:code-reviewer`

Prompt: review the full branch diff (`git diff <BASE>..HEAD`, literal SHA) for correctness, logic defects, edge cases, and API-contract problems. Category `general`.

### 2. Scope check — `general-purpose`, read-only

Prompt must ask:
- Can this branch be split into meaningful independent parts? Name the split if so.
- Are files/hunks touched that are not needed for the stated goal (drive-by changes)?
- When a parent PR/issue is given: does this extraction stand alone, and what of the parent does it silently depend on?
Category `scope`. Splittability is a finding, not a blocker — verdict rubric decides.

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

## Phase 2 — Test review — `oh-my-claudecode:test-engineer`

Prompt: review tests changed/added on this branch. Check that:
- Each assertion validates observable expected behavior, not incidental output.
- Tests do not reach into implementation details or private APIs (`_underscore` members, internal DOM structure that is not part of the contract) unless no public path exists.
- Setup/teardown is sound; no order dependence.
Category `tests`. Mutation analysis is NOT this agent's job — phase 4 handles it.
