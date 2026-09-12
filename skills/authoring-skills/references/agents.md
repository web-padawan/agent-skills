# Plugin agents — conventions for `agents/`

Subagent definitions live in `agents/` at the plugin root. Invoke one with
`subagent_type: "agent-skills:<name>"`. New or changed agents load after
`claude plugin update agent-skills@local` plus a session restart (or `/reload-plugins`).

## When an agent, when skill prose

When a pass has a **static contract reused across runs**, make an agent. Such a contract has
fixed questions, a fixed category, and a fixed output format. The definition becomes the
single source. The references of the skill shrink to a table row. The prompt that invokes the
agent shrinks to run-specific facts.

Keep the pass as skill prose when a skill invokes it once. Also keep the pass as prose when
its content is mostly dynamic.

Two further reasons decided the 2026-08 migration. First, the `tools` frontmatter of an agent
makes read-only **structural** instead of prompted. Second, agents that ship with the plugin
remove dependencies on agent types that the teammate may not have installed.

## Frontmatter

```markdown
---
name: <kebab-name>            # equal to the filename
description: <one line> Used exclusively by the agent-skills review skills — not for general delegation.
tools: Read, Glob, Grep, Bash
disallowedTools: Write, Edit
---
```

- The **exclusive-use sentence is mandatory**. The main loop sees agent descriptions as
  delegation targets. Without the boundary, a "review my code" request can route into a
  pipeline agent that expects a context file that does not exist.
- Reviewer agents get both the `tools` allowlist **and** `disallowedTools: Write, Edit`.
  The allowlist documents intent. The denylist survives default-inheritance surprises.
- No `model:`. Agents inherit the session model unless a pass genuinely needs a tier.

## Body shape

Target ≤100 lines. Put the role and read-only statement first. Then add the questions, the
output contract (finding-line format, cap, `NO FINDINGS` rule), a **Verify before reporting**
section, and the closing delivery sentence.

See `agents/test-reviewer.md` for the single-category example. See `agents/code-reviewer.md`
for an example that carries eight categories. A pass takes another question when that
question shares the inputs of the first question. Each question still reports under its own
category.

## Static in the body, dynamic in the prompt

The definition carries everything stable: questions, category, output contract, tier
guidance, verification rules. The prompt from the skill that invokes the agent carries only
what changes per run. That is the path of the shared context file, literal SHAs, run-specific
facts (the one change under review, the conventions doc name), and the delivery clause. Never
restate the contract in the prompt. One source, no drift.

## Fallback clause

Skills reference agents by type. A skill must also survive a copy out of the plugin. Use the
convention of `references/pipeline.md` §3: "only when the plugin agents are
unavailable: use `general-purpose` and paste the body of the corresponding `agents/<name>.md`
into the prompt."
