# The three lenses — field contracts

One trio per change under review. Read-only, always.

The three reviews run as **three separate agents**, not one agent asked three questions. A single agent collapses the lenses into one narrative and loses the disagreements — the boundary review calling a change expensive while the impact review calls its blast radius trivial is exactly the tension worth surfacing, and it only exists if the two never see each other.

| Review | Agent | Category |
| --- | --- | --- |
| Architectural | `oh-my-claudecode:architect` | `architecture` |
| Boundary | `oh-my-claudecode:architect` (second instance) | `boundary`, or `api` when the boundary is public API |
| CIA — change impact analysis | `oh-my-claudecode:critic` | `impact` |

Fall back to `general-purpose` when OMC agents are unavailable.

Every prompt carries: the context the agent needs (branch, base SHA, the change's description — or the shared context file path when the invoking workflow keeps one), the **one** change this agent reviews (`file:line-range` plus a one-sentence description — an agent handed a whole list writes a survey instead of a review), its own field contract verbatim from the sections below, and the invoker's delivery clause.

## 1. Architectural review — category `architecture`

Ask: what does this change actually do to the shape of the code, and what does that cost later?

```
### <file>:<line-range> — <short name>
Observed behavior: <what the change makes the code do, stated without judgement>
Risk: <what could go wrong, or what becomes fragile>
Consequences: <what follows if the risk lands — for the code, for consumers, for future changes>
Suggestion: <the smallest change that lowers the risk>
Severity: <A|B|C>
```

- `Observed behavior` is descriptive, not evaluative. An agent that editorialises here has already decided the verdict and will bend the other four fields to it.
- `Suggestion` is the **smallest** change that helps. No rewrites, no speculative extensibility, no "consider extracting a framework". If the shape is fine, write `none — the shape is sound` and say why.
- Premature abstraction (a generalization with one caller) and its opposite (copy-paste that will fork) both belong under `Risk`.
- Worth stating under `Consequences` when it applies: what a maintainer six months from now is most likely to misread.

## 2. Boundary review — category `boundary` (`api` when the boundary is public API)

Ask: what promise does this change make, to whom, and how expensive is it to take back?

```
### <file>:<line-range> — <short name>
Boundary affected: <which one — public API, package export, event contract, mixin/host contract, data shape, DOM structure, CSS custom property or part, storage/wire format>
Consumers: <who is on the other side, named — sibling components, applications, tests, downstream packages. "none yet" is a valid and important answer>
Promise created: <what this commits us to, phrased as the promise a consumer will rely on>
Why hard to change: <what makes walking it back expensive — released surface, no deprecation path, implicit dependents, data already written, timing others now depend on>
Proposed alternative: <a shape that keeps the capability with a cheaper promise, or "none — the promise is correct" with the reason>
Severity: <A|B|C>
```

- `Consumers` must be **named**, found by searching the repo, not guessed. An unnamed consumer list makes the severity unjustifiable in either direction.
- `Promise created` is written from the consumer's side: "the `opened` property can be set before the element is attached", not "we moved the listener". A promise nobody could state in one sentence is usually an accidental one — which is itself the finding.
- In a component library a released public API cannot change without a breaking change. That is what makes this the most valuable lens in the trio, and the one a self-reviewer most reliably underweights.

## 3. Change impact analysis — category `impact`

Ask: how far does this reach, and what has to be true before it is safe to merge?

```
### <file>:<line-range> — <short name>
Affected areas: <modules, packages, features touched directly>
Ripple effects: <what changes behavior indirectly, one step out>
Propagation paths: <the concrete chain — A calls B which reads C; name the files>
Risk criticality: <A|B|C, with the one-line reason>
Mitigation path: <what would reduce the risk before merge>
Unblock conditions: <what must be true for this to be safe to merge — a test that exists, a consumer confirmed unaffected, a flag added>
```

- `Propagation paths` names files. A path stated abstractly ("this could affect overlays") is not a path; find the call chain or say no path was found.
- `Unblock conditions` are checkable statements, not intentions. "A test asserts the listener is removed on detach" is a condition; "be careful with detach" is not.
- `Mitigation path` and `Unblock conditions` are what make an A finding actionable in a report-only review — the report cannot fix anything, so it must say precisely what would.

## Severity mapping

The trio's own severity words map onto A/B/C. These are proposals — the invoking workflow's triage assigns the final tier (self-review does this in its stage 3; a standalone arch-review run verifies and assigns it itself).

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
