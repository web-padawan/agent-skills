# Stage 2b — Deep review, per significant change

One trio per significant change from stage 1's inventory. Read-only, like every other stage.

The three reviews run as **three separate agents**, not one agent asked three questions. A single agent collapses the lenses into one narrative and loses the disagreements — the boundary review calling a change expensive while the impact review calls its blast radius trivial is exactly the tension worth surfacing, and it only exists if the two never see each other.

| Review | Agent | Category |
| --- | --- | --- |
| Architectural | `oh-my-claudecode:architect` | `architecture` |
| Boundary | `oh-my-claudecode:architect` (second instance) | `boundary`, or `api` when the boundary is public API |
| CIA — change impact analysis | `oh-my-claudecode:critic` | `impact` |

Fall back to `general-purpose` when OMC agents are unavailable, as elsewhere in this skill.

## Batching

3 agents per change plus the breadth passes adds up fast: even a refactor at budget 4 is 12 deep agents on top of 6 breadth agents.

Cap each message at roughly **6 agents**:

- Message 1 — the breadth passes.
- Message 2 — the trios for the top 2 ranked changes.
- Message 3 onward — two more changes per message until the budget is spent.

Do not put every trio in the stage-2 message with the breadth passes. Measured on a real refactor branch, an 18-agent single message is where deep agents start returning surveys instead of reviews, and one lost report costs a whole lens on a change. Three or four messages of six cost some wall-clock and buy every agent a full run.

The batch boundary is a launch detail, not a barrier for triage — stage 3 still waits for everything before verifying anything.

## Prompt shape — shared by all three

Every prompt carries:

- `read <report-dir>/context.md first` — it holds the branch, the literal `<BASE>` SHA, the change type, and the ranked inventory.
- The one change this agent reviews: its rank, `file:line-range`, and the inventory's one-sentence description. **One change per agent** — an agent handed the whole list writes a survey instead of a review.
- Its own field contract, verbatim, from the sections below.
- The delivery clause from analysis.md's **Delivery** section. That reference is not optional; a prompt without it loses its report.
- `run_in_background: false`, no `name`.

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
- `Mitigation path` and `Unblock conditions` are what make an A finding actionable in a report-only skill — the report cannot fix anything, so it must say precisely what would.

## Severity mapping

The trio's own severity words map onto the skill's A/B/C. **Stage 3 still assigns the final tier** — these are proposals.

- **Architectural `Severity`** — **A** when the consequence is wrong behavior, or a change a follow-up could not make without a breaking change. **B** for cost-of-change debt. **C** for taste.
- **Boundary `Severity`** — a promise that cannot be walked back without a breaking change is **A**, always. `Consumers: none yet` drops it to **B**: an unreleased boundary is still cheap to move. Nothing else in this skill discriminates as sharply, so apply it literally.
- **CIA `Risk criticality`** — **A** when a propagation path reaches released behavior with no test on it. **B** when the path is internal or test-covered. **C** when the ripple is cosmetic.

## Rolling blocks into findings

Each agent returns its **block**, then **one or more finding lines** in the standard contract from analysis.md:

```
<category> | <file>:<line> | <A|B|C> | <claim>
```

The block is the evidence and goes into the report verbatim under the change's own heading. The lines are what stage 3 verifies, dedups and tiers, which is what keeps the tier counts and the report's category sections working unchanged.

A block with no finding lines is an unfinished report, not a clean one. When a change genuinely reviews clean, the agent returns the block **and** a `NO FINDINGS` line — a clean boundary review is exactly the record worth having six months later, so the block is never optional.
