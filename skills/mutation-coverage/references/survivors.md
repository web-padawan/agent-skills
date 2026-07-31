# Classifying survivors

Work out *why* no test catches each survivor before writing anything. Every
survivor ends up in one of these classes; the class decides the action.

## Plain coverage gap

Nobody asserts on the effect. Write the missing test.

## Masked write

Another component recomputes the same field (e.g. a list element re-deriving
`file.status` that the mixin already set), so removing or corrupting the write
is invisible in the default fixture. Kill it with a fixture that bypasses the
masker: a custom slotted element, an unattached element, or a spy taken before
the recompute.

## Self-referential assertion

A test comparing against the component's own value (`expect(x).to.equal(el.i18n.foo)`)
mutates together with the source, so it can never fail. Assert the literal
value instead.

## Untestable helper

The test helper prevents the behavior from being observable — e.g. synthetic
test events dispatched as non-cancelable make `preventDefault()` unobservable.
Fix the helper, don't skip the line.

## Structurally unkillable

Removal or mutation has no observable behavior:

- `type: String` in a Lit property declaration (Lit's default converter);
- `type` on private properties never set via attribute;
- `sync: true` when nothing observes synchronously;
- a `super.ready()` (or similar chained call) with only empty implementations above;
- unused (dead) declarations.

Do NOT write hacky tests for these. Record them in the report with a one-line
justification, and flag dead code as a removal candidate for a separate PR.

## Equivalent mutant (Stryker only)

The mutated program behaves identically to the original for every input the
public API can produce (e.g. `>=` vs `>` where the boundary value is
unreachable, a string literal only used as a debug label). Same treatment as
structurally unkillable: document, don't force a test.

## Known-untested by design (Stryker only)

Mutants inside `static get styles()` / `static get lumoInjector()` are covered
by visual regression tests, not unit assertions — the ignore plugin excludes
them up front (status `Ignored`). If one still shows up (e.g. plugin not
active), classify it here, never write a `getComputedStyle` assertion for a
CSS custom property override.
