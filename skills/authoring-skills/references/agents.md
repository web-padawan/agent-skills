# Plugin agents — conventions for `agents/`

Subagent definitions live in `agents/` at the plugin root and are invoked with
`subagent_type: "agent-skills:<name>"`. New or changed agents load after
`claude plugin update agent-skills@local` plus a session restart (or `/reload-plugins`).

## When an agent, when skill prose

Make an agent when a pass has a **static contract reused across runs** — fixed questions, a
fixed category, a fixed output format. The definition becomes the single source; the skill's
references shrink to a table row and the invoking prompt to run-specific facts. Keep it as
skill prose when the pass is invoked once, or when its content is mostly dynamic.

Two further reasons that decided the 2026-08 migration: an agent's `tools` frontmatter makes
read-only **structural** instead of prompted, and shipping agents with the plugin removes
dependencies on agent types the teammate may not have installed.

## Frontmatter

```markdown
---
name: <kebab-name>            # equal to the filename
description: <one line> Used exclusively by the agent-skills review skills — not for general delegation.
tools: Read, Glob, Grep, Bash
disallowedTools: Write, Edit
---
```

- The **exclusive-use sentence is mandatory**: agent descriptions are visible to the main
  loop as delegation targets, and without the boundary a "review my code" request can route
  into a pipeline agent that expects a context file that does not exist.
- Reviewer agents get both the `tools` allowlist **and** `disallowedTools: Write, Edit` —
  the allowlist documents intent, the denylist survives default-inheritance surprises.
- No `model:` — agents inherit the session model unless a pass genuinely needs a tier.

## Body shape

Target ≤100 lines: role and read-only statement first, then the questions, the output
contract (finding-line format, cap, `NO FINDINGS` rule), a **Verify before reporting**
section, and the closing delivery sentence. See `agents/test-reviewer.md` for the single-category
example and `agents/code-reviewer.md` for one carrying eight — a pass takes another question
when it shares the first one's inputs, and each still reports under its own category.

## Static in the body, dynamic in the prompt

The definition carries everything stable: questions, category, output contract, tier
guidance, verification rules. The invoking skill's prompt carries only what changes per run:
the shared context file path, literal SHAs, run-specific facts (the one change under review,
the conventions doc name), and the delivery clause. Never restate the contract in the
prompt — one source, no drift.

## Fallback clause

Skills reference agents by type but must survive being copied out of the plugin. The
convention, used in `references/pipeline.md` §3: "when the plugin's agents are
unavailable, use `general-purpose` and paste the full body of `agents/<name>.md` into the
prompt."
