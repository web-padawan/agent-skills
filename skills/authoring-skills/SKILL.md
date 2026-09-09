---
name: authoring-skills
description: Author a new agent skill or improve an existing one in this plugin - write the SKILL.md frontmatter and description, structure the body, split references, and fix skills that under- or over-trigger. Use when asked to create/write a skill, make a SKILL.md, improve/refactor a skill, or fix a skill's description.
---

# Authoring Skills

This skill is a workflow to write a new skill or to improve an existing one. The result
must trigger reliably, stay maintainable, and earn its place in context. The workflow
follows the Anthropic article "Lessons from building Claude Code: how we use skills"
(Jun 2026) and the conventions of the skills in this repository.

A skill is a **folder, not just a markdown file**. It holds a `SKILL.md` plus optional
`references/` (load-on-demand markdown), `scripts/` (helpers), and `assets/` (templates).
Treat the whole folder as context engineering.

## When to use

- You want to convert a repeatable workflow, review procedure, or verification technique
  into a reusable skill in this plugin.
- An existing skill under-triggers (never fires when it should) or over-triggers (fires
  for the wrong tasks). The cause is usually the `description`.
- A `SKILL.md` has grown too large and needs a split into `references/`.

## When NOT to use

- The behavior is a one-off. A one-off belongs in a note, not in a skill.
- The content only restates what the model already does well (see Anti-patterns).

## Step 0 — Is a skill the right vessel?

1. **Does it fit cleanly in one category?** The best skills fit one job. A skill that
   straddles several jobs confuses the agent. If your idea spans two jobs, split it.
   See [references/skill-types.md](references/skill-types.md) for the four-category
   taxonomy of this repo and a "which bucket?" decision aid.
2. **Does it move the model away from its defaults?** If not, write nothing.
3. **Will you reuse it?** A one-off becomes a note. A reused workflow becomes a skill.

## Step 1 — Write the description first (the discovery trigger)

The agent scans the `description` of every skill to decide if a skill exists for the
request. The `description` is **not a summary but a description of *when to trigger*.**

Write it for the model. Lead with the literal phrases that a user would type. Enumerate
the situations that it covers. If a sibling skill could also match, add a boundary
clause. Keep the third-person present. This also applies to manual-only skills, because
the description holds the boundary against siblings.

Litmus test: read *only* the description and predict which prompts fire it. If you cannot
predict, the agent cannot either. Fix the description before you touch the body.
Patterns, worked before/after examples, and the full test are in
[references/descriptions.md](references/descriptions.md).

## Step 2 — Choose the body shape

Pick the smallest archetype that fits. Grow it later. Most good skills start as a few
lines and one gotcha.

| Archetype | Use for | Representative example |
|---|---|---|
| **Inline technique** (<80 lines, no subfolders) | A single self-contained procedure | `guided-review` |
| **Phase / reference-table workflow** | A multi-step process where each step has depth | `self-review` |
| **Deep reference + guardrails** | A tool or engine with many footguns, budgets, caveats | `mutation-coverage` |

Do not build a `references/` tree before you need it.

## Step 3 — Write the body

1. Open with one or two sentences on what the skill does and what it assumes.
   Write the body in Simplified Technical English. `.claude/rules/writing-style.md`
   gives the limits: 20 words per instruction, imperative steps, no semicolons or dashes.
2. **Lead with the gotchas.** The highest-signal content is what the agent gets wrong by
   default. Prefer concrete "X is actually Y" facts over generic advice. Grow this
   section as new edge cases surface.
3. **Do not railroad.** Give facts and constraints, not a rigid transcript. Prescribe an
   order only when the order matters, for example for destructive or safety steps.
4. **Store scripts. Let the agent compose.** Ship helpers for boilerplate, so that the
   agent spends turns on decisions, not on scaffolding. Reference them by a path
   relative to the skill root, with the `${CLAUDE_PLUGIN_ROOT}` fallback that this repo
   uses.
5. If the skill has many discrete rules, end with an **Agent Guidelines / Rules** list.
   The list is a scannable contract that the agent can re-check.

## Step 4 — Progressive disclosure: inline vs bundled

Keep `SKILL.md` to the trigger plus the always-needed essentials. The hard ceiling is
150 lines, the target is under 100. Push depth into files that load on demand:

- **`references/<topic>.md`** when a section serves only a sub-case, or when the body
  grows past the length budget. Link it inline, so that the agent knows that it exists.
- **`scripts/`** for any deterministic step. **`assets/`** for output templates.

Rule of thumb: a heading that matters to only a fraction of invocations belongs in
`references/`. A heading that matters every time stays inline.

## Step 5 — Frontmatter

Required: `name` (kebab-case, equal to the directory name) and `description`. Optional:
`argument-hint`, `allowed-tools`, `disable-model-invocation`. Set
`disable-model-invocation: true` on any skill that is expensive to run or that can post
outside the machine. The full field reference and a linting checklist are in
[references/frontmatter.md](references/frontmatter.md).

To start from a skeleton, copy [assets/SKILL.template.md](assets/SKILL.template.md). It
has frontmatter stubs and commented section placeholders for each archetype.

## Step 5b — Agents (plugin subagents)

A pass with a static contract that every run reuses belongs in `agents/` at the plugin
root, not in skill prose. The agent definition carries the questions and the output
contract. The skill prompt carries only run-specific facts. The conventions (frontmatter
shape, the mandatory exclusive-use description clause, read-only tool rules, the fallback
clause) are in [references/agents.md](references/agents.md).

## Step 6 — Verify before shipping

1. **Trigger test:** write 3 to 5 prompts that should fire the skill and 2 to 3 that should
   not. Read only the `description` and predict the result. Adjust until correct.
2. **Cold-read test:** can an agent with no prior context follow the body without a
   guess at paths or commands? Resolve every relative path.
3. **Style test:** read each new or changed paragraph against
   `.claude/rules/writing-style.md`. Count the words in the longest sentence. Search the
   diff for `;` and `—` outside code blocks.
4. **Live test:** reinstall the plugin (`claude plugin update agent-skills@local` after
   the commit). Run the skill once on a real case before you rely on it.

## Improving an existing skill

Diagnose the symptom, then make the smallest fix:

- **Under-triggers**: the description lacks trigger phrases. Add the literal words.
- **Over-triggers**: the description is too broad or overlaps a sibling. Add a boundary.
- **Fires but underperforms**: the gotchas lack the failure, or the skill railroads. Add
  the failure to the gotchas section and loosen over-specific steps.
- **Too long / slow to load**: move sub-case sections into `references/`.

Always capture the failure as a gotcha, so that it cannot recur. This is how skills
compound in value.

## Anti-patterns

- **Stating the obvious.** A restatement of model defaults adds context cost and zero value.
- **Straddling categories.** One skill, one job.
- **Description-as-summary.** It omits trigger words. The skill silently never fires.
- **Railroading.** A rigid transcript breaks when reality differs.
- **Dense prose.** Long sentences, semicolons and dashes hide the instruction from the agent.
- **Premature `references/`.** A split before the skill is big enough.
- **Reconstructing boilerplate in prose** instead of a shipped script.
- **Baking in environment specifics** (paths, repo names) instead of resolution at run
  time. The skills in this repo detect repo commands in a setup stage.
