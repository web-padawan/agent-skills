# The three lenses

One trio per change under review. Read-only, always.

The three reviews run as **three separate agents**, not one agent asked three questions. A single agent collapses the lenses into one narrative and loses the disagreements — the boundary review calling a change expensive while the impact review calls its blast radius trivial is exactly the tension worth surfacing, and it only exists if the two never see each other.

| Review | Agent | Category |
| --- | --- | --- |
| Architectural | `agent-skills:lens-architectural` | `architecture` |
| Boundary | `agent-skills:lens-boundary` | `boundary`, or `api` when the boundary is public API |
| CIA — change impact analysis | `agent-skills:lens-impact` | `impact` |

**The field contracts live in the agent definitions** — [`../../agents/lens-architectural.md`](../../agents/lens-architectural.md), [`../../agents/lens-boundary.md`](../../agents/lens-boundary.md), [`../../agents/lens-impact.md`](../../agents/lens-impact.md) (fallback `${CLAUDE_PLUGIN_ROOT}/agents/<name>.md`). Each agent carries its block format, field rules, finding-line contract, and verification rules in its system prompt, so the invoker does **not** paste contracts into prompts.

Every prompt carries: the context the agent needs (branch, base SHA, the change's description — or the shared context file path when the invoking workflow keeps one), the **one** change this agent reviews (`file:line-range` plus a one-sentence description — an agent handed a whole list writes a survey instead of a review), and the invoker's delivery clause.

**Fallback** — only when the plugin's agents are unavailable (e.g. this file was copied out of the plugin): use `general-purpose` and paste the full body of the corresponding `agents/lens-*.md` file into the prompt.

## Severity mapping

The trio's own severity words map onto A/B/C. These are proposals — the invoking workflow's triage assigns the final tier (self-review does this in its stage-2 triage when --deep ran; a standalone arch-review run verifies and assigns it itself).

- **Architectural `Severity`** — **A** when the consequence is wrong behavior, or a change a follow-up could not make without a breaking change. **B** for cost-of-change debt. **C** for taste.
- **Boundary `Severity`** — a promise that cannot be walked back without a breaking change is **A**, always. `Consumers: none yet` drops it to **B**: an unreleased boundary is still cheap to move. Nothing else discriminates as sharply, so apply it literally.
- **CIA `Risk criticality`** — **A** when a propagation path reaches released behavior with no test on it. **B** when the path is internal or test-covered. **C** when the ripple is cosmetic.

## Rolling blocks into findings

Each agent returns its **block**, then **one or more finding lines** in the standard contract:

```
<category> | <file>:<line> | <A|B|C> | <claim>
```

The block is the evidence and goes into the report verbatim under the change's own heading. The lines are what triage verifies, dedups and tiers.

A block with no finding lines is an unfinished report, not a clean one. When a change genuinely reviews clean, the agent returns the block **and** a `NO FINDINGS` line — a clean boundary review is exactly the record worth having six months later, so the block is never optional.
