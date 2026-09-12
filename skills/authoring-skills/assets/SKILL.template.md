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

<!-- Write the body in Simplified Technical English. See .claude/rules/writing-style.md.
     Use no more than 20 words in an instruction. Use the imperative for steps.
     Do not use semicolons or em-dashes. -->

<!-- One or two sentences: what this skill does and what it assumes.
     State what it makes the agent do that the agent does not do well by default.
     Cut anything that the model already does well. -->

## When to use this skill

<!-- The situations that should trigger it. Mirror the triggers of the description. -->
- <situation 1>
- <situation 2>

## When NOT to use it

<!-- Boundaries. One-off work does not need a skill. Cut a restatement of model defaults. -->
- <non-trigger / sibling-skill case>

<!-- ===================================================================== -->
<!-- PICK ONE ARCHETYPE BELOW AND DELETE THE OTHER TWO (see SKILL.md Step 2) -->
<!-- ===================================================================== -->

<!-- ---------- ARCHETYPE A: INLINE TECHNIQUE (<~80 lines, no subfolders) ----------
     For a single self-contained procedure. Example shape: guided-review.

## Gotchas

[Highest-signal content. Real failure points that the agent hits by default.
Prefer concrete "X is actually Y" facts over generic advice. Grow this list over time.]
- <gotcha 1>

## Technique / steps

1. <step>
2. <step>

## Rules

- <hard rule>
-->

<!-- ---------- ARCHETYPE B: PHASE / REFERENCE-TABLE WORKFLOW ----------
     For a multi-step process where each step has depth. Example: self-review.
     Keep the table inline. Push the detail of each phase into references/.

## Overview

[A one-paragraph summary of the loop or flow.]

## Phases

| Phase | Summary | Reference |
|-------|---------|-----------|
| 1 | <what> | [references/phase-1.md](references/phase-1.md) |
| 2 | <what> | [references/phase-2.md](references/phase-2.md) |

## Gotchas

- <gotcha>

## Safety rules

- <hard constraint, in particular for destructive or irreversible steps>
-->

<!-- ---------- ARCHETYPE C: DEEP REFERENCE + GUARDRAILS ----------
     For a tool or engine with many footguns, budgets, and caveats. Example: mutation-coverage.

## Discovery / usage

[How to find the authoritative usage. Prefer bundled recipes over a new derivation.]

## Common pitfalls

- <wrong-looking-correct usage 1>
- <wrong-looking-correct usage 2>

## Iteration budget

[How hard to try before you stop. Cap the attempts. Stop loudly.]

## Reporting results

[How to present output honestly, with caveats.]
-->

<!-- ===================================================================== -->

## Agent guidelines

<!-- Optional but common: a scannable numbered contract of rules that the agent can
     re-check. -->
1. <guideline>
2. <guideline>

## References

<!-- List bundled files, so that the agent knows that they exist and loads them on demand.
     Paths are relative to the skill root. If the skill reads files at run time, note the
     ${CLAUDE_PLUGIN_ROOT} fallback. Delete this section if the skill is fully inline. -->
| Topic | Location |
|---|---|
| <topic> | `references/<file>.md` |
| <output template> | `assets/<file>.md` |
