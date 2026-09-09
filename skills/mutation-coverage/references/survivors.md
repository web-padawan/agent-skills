# Classifying survivors

Before you write anything, determine why no test catches each survivor. Every
survivor belongs to one of these classes. The class decides the action.

## Plain coverage gap

Nobody asserts on the effect. Write the missing test.

## Masked write

Another component recomputes the same field. For example, a list element
re-derives `file.status` that the mixin already set. So the default fixture does
not show a removed or corrupted write. Kill the survivor with a fixture that
bypasses the masker:

- a custom slotted element
- an unattached element
- a spy taken before the recompute

## Self-referential assertion

A test that compares against a value from the component itself
(`expect(x).to.equal(el.i18n.foo)`) mutates together with the source. So the test
can never fail. Assert the literal value instead.

## Untestable helper

The test helper makes the behavior unobservable. For example, synthetic test
events dispatched as non-cancelable make `preventDefault()` unobservable. Fix the
helper. Do not skip the line.

## Structurally unkillable

Removal or mutation has no observable behavior:

- `type: String` in a Lit property declaration (the Lit default converter)
- `type` on private properties that no attribute ever sets
- `sync: true` with no synchronous observer
- a `super.ready()` (or similar chained call) with only empty implementations above
- unused (dead) declarations

Do NOT write hacky tests for these. Record them in the report with a one-line
justification. Flag dead code as a removal candidate for a separate PR.

## Equivalent mutant (Stryker only)

The mutated program behaves identically to the original for every input that the
public API can produce. Examples: `>=` compared with `>` where the boundary value
is unreachable, or a string literal that only serves as a debug label. Treat it
like a structurally unkillable survivor: document it, do not force a test.

## Known-untested by design (Stryker only)

Visual regression tests cover mutants inside `static get styles()` /
`static get lumoInjector()`, not unit assertions. The ignore plugin excludes these
mutants up front (status `Ignored`). If one still appears, for example because the
plugin is not active, classify it here. Never write a `getComputedStyle` assertion
for a CSS custom property override.
