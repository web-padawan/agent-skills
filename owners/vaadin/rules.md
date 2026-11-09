# Owner rules: vaadin

The review plan quotes these rules into the context file of each review of a vaadin repository.

## From agents/change-reviewer.md

- A public surface also includes a slot, a CSS custom property, a CSS part and a `.d.ts` entry. A change to one of them is a public surface change.
- In the `Boundary:` line of a block, a CSS part or a CSS custom property is a `styling hook`.

## From agents/code-reviewer.md

- Logic: an element is correct when it is detached and attached again.
- Comments: no comment longer than 1 line in a CSS file.

## From agents/test-reviewer.md

- Structure: a style change pinned only by `getComputedStyle` in a unit test is a finding when the testing guideline of the repository asks for visual tests. A guideline backs it, so it is B, not C.
- Implementation reaching: internal DOM outside the contract of the element counts as internal structure.
