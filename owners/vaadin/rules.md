# Owner rules: vaadin

The review plan quotes these rules into the context file of each review of a vaadin repository.

## From agents/change-reviewer.md

- Significant change rule (1), public surface, also matches a CSS custom property, a CSS part and a `.d.ts` entry.
- In the `Boundary:` line of a block, a CSS part or a CSS custom property is a `styling hook`.

## From agents/code-reviewer.md

- Logic: an element is correct when it is detached and attached again.
- Comments: no comment longer than 1 line in a CSS file.

## From agents/test-reviewer.md

- Structure: a style change pinned only by `getComputedStyle` in a unit test is a finding when the testing guideline of the repository asks for visual tests. A guideline backs it, so it is B, not C.
- Implementation reaching: internal DOM outside the contract of the element counts as internal structure.

## From references/severity.md

- CI: the `ci:` digest also settles the state of the visual baselines for the head.
- Tests tie-break: a path that another theme pins is pinned elsewhere, so the finding is B.
- A stale but passing visual baseline is B when the whole fix is to regenerate it. The report must still say that the committed baseline does not match the code.
- A process step can be a `.d.ts` entry, a dev page, or a companion PR in vaadin/flow-components.
- A routed question names the theme to check. A parity question names the Flow wrapper API that the change must match.
