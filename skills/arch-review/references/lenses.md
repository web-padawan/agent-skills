# The three lenses

One trio per change under review. Read-only, always.

The three reviews run as **three separate agents**, not one agent asked three questions. A single agent collapses the lenses into one narrative and loses the disagreements — the boundary review calling a change expensive while the impact review calls its blast radius trivial is exactly the tension worth surfacing, and it only exists if the two never see each other.

| Review | Agent | Category |
| --- | --- | --- |
| Architectural | `agent-skills:lens-architectural` | `architecture` |
| Boundary | `agent-skills:lens-boundary` | `boundary`, or `api` when the boundary is public API |
| CIA — change impact analysis | `agent-skills:lens-impact` | `impact` |

**The field contracts live in the agent definitions** — [`../../../agents/lens-architectural.md`](../../../agents/lens-architectural.md), [`../../../agents/lens-boundary.md`](../../../agents/lens-boundary.md), [`../../../agents/lens-impact.md`](../../../agents/lens-impact.md) (fallback `${CLAUDE_PLUGIN_ROOT}/agents/<name>.md`). Each agent carries its block format, field rules, finding-line contract, and verification rules in its system prompt, so the invoker does **not** paste contracts into prompts.

Every prompt carries: the context the agent needs (branch, base SHA, the change's description — or the shared context file path when the invoking workflow keeps one), the **one** change this agent reviews (`file:line-range` plus a one-sentence description — an agent handed a whole list writes a survey instead of a review), and the invoker's delivery clause.

**Fallback** — only when the plugin's agents are unavailable (e.g. this file was copied out of the plugin): use `general-purpose` and paste the full body of the corresponding `agents/lens-*.md` file into the prompt.

## Severity

The lens severity words map onto A/B/C in
[`../../../references/severity.md`](../../../references/severity.md) § Lens severities. They are
proposals — the invoking workflow's triage assigns the final tier.

## Rolling blocks into findings

Each agent returns its **block**, then **one or more finding lines** in the standard contract:

```
<category> | <file>:<line> | <A|B|C> | <claim>
```

The block is the evidence; the lines are what triage verifies, dedups and tiers. Every block is always **returned** by its agent — the invoker decides how much of it reaches the report, per SKILL.md step 4: full prose for an A-tier change, one condensed line per lens for a B/C-only or clean one. The agent never pre-trims on the invoker's behalf, and the invoker never drops a finding to save room.

A block with no finding lines is an unfinished report, not a clean one. When a change genuinely reviews clean, the agent returns the block **and** a `NO FINDINGS` line — a clean boundary verdict is exactly the record worth having six months later, so the block is never optional.
