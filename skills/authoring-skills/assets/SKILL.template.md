---
name: my-skill-name                 # kebab-case; MUST match the skill folder name
description: <one trigger-shaped sentence — lead with the verbs/phrases a user
  would type, enumerate the situations it covers, add a "not for…" boundary
  naming any sibling skill that could also match. Third-person present. See
  references/descriptions.md.>
# argument-hint: "<thing the skill takes>"  # only if invoked with arguments
# disable-model-invocation: true            # if expensive or posts externally
# allowed-tools: Read, Grep, Glob, Bash(git:*), Bash(gh:*)  # only to constrain access
---

# my-skill-name

<!-- One or two sentences: what this skill does and what it assumes.
     State the value proposition — what it makes the agent do that it would not
     do well by default. (Cut anything the model already does well.) -->

## When to use this skill

<!-- The situations that should trigger it. Mirror the description's triggers. -->
- <situation 1>
- <situation 2>

## When NOT to use it

<!-- Boundaries. One-off work → not a skill. Restating model defaults → cut. -->
- <non-trigger / sibling-skill case>

<!-- ===================================================================== -->
<!-- PICK ONE ARCHETYPE BELOW AND DELETE THE OTHER TWO (see SKILL.md Step 2) -->
<!-- ===================================================================== -->

<!-- ---------- ARCHETYPE A: INLINE TECHNIQUE (<~80 lines, no subfolders) ----------
     For a single self-contained procedure. Example shape: guided-review.

## Gotchas

[Highest-signal content. Real failure points the agent hits by default.
Prefer concrete "X is actually Y" facts over generic advice. Grow over time.]
- <gotcha 1>

## Technique / Steps

1. <step>
2. <step>

## Rules

- <hard do/don't>
-->

<!-- ---------- ARCHETYPE B: PHASE / REFERENCE-TABLE WORKFLOW ----------
     For a multi-step process where each step has depth. Example: self-review.
     Keep the table inline; push each phase's detail into references/.

## Overview

[One-paragraph summary of the loop/flow.]

## Phases

| Phase | Summary | Reference |
|-------|---------|-----------|
| 1 | <what> | [references/phase-1.md](references/phase-1.md) |
| 2 | <what> | [references/phase-2.md](references/phase-2.md) |

## Gotchas

- <gotcha>

## Safety Rules

- <hard constraint, esp. for destructive/irreversible steps>
-->

<!-- ---------- ARCHETYPE C: DEEP REFERENCE + GUARDRAILS ----------
     For a tool/engine with many footguns, budgets, caveats. Example: mutation-coverage.

## Discovery / Usage

[How to find the authoritative usage; prefer bundled recipes over re-deriving.]

## Common pitfalls

- <wrong-looking-correct usage 1>
- <wrong-looking-correct usage 2>

## Iteration budget

[How hard to try before giving up; cap attempts; give up loudly.]

## Reporting results

[How to present output honestly, with caveats.]
-->

<!-- ===================================================================== -->

## Agent Guidelines

<!-- Optional but common: a scannable numbered do/don't contract the agent can
     re-check. -->
1. <guideline>
2. <guideline>

## References

<!-- List bundled files so the agent knows they exist and loads them on demand.
     Paths are relative to the skill root; note the ${CLAUDE_PLUGIN_ROOT}
     fallback if the skill reads files at run time. Delete if fully inline. -->
| Topic | Location |
|---|---|
| <topic> | `references/<file>.md` |
| <output template> | `assets/<file>.md` |
