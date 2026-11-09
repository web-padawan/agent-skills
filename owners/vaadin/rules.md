# Owner rules: vaadin

The review plan quotes these rules into the context file of each review of a vaadin repository.

## From agents/change-reviewer.md

- Significant change rule (1), public surface, also matches a CSS custom property, a CSS part and a `.d.ts` entry.
- In the `Boundary:` line of a block, a CSS part or a CSS custom property is a `styling hook`.

## From agents/code-reviewer.md

- Comments: no comment longer than 1 line in a CSS file.

## From references/severity.md

- Tests tie-break: a path that another theme pins is pinned elsewhere, so the finding is B.
- A process step can be a `.d.ts` entry, a dev page, or a companion PR in vaadin/flow-components.
- The configuration to check in a routed `(design)` question is the theme.
- A `(parity)` question names the wrapper API that the change must match, for example of Flow or React.
