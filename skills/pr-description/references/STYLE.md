# Style

The rules below are derived from merged `vaadin/web-components` PRs that read well:
[#12030](https://github.com/vaadin/web-components/pull/12030),
[#11964](https://github.com/vaadin/web-components/pull/11964),
[#12047](https://github.com/vaadin/web-components/pull/12047),
[#11153](https://github.com/vaadin/web-components/pull/11153).

## Bullets

**Past tense, one behavior per bullet, identifiers in backticks.**

> - Added `role="slider"` and `tabindex="0"` to the `splitter` element making it focusable
> - Added `aria-valuemin`, `aria-valuemax` and `aria-valuenow` announced by screen readers
> - Added `KeyboardMixin` and logic for Arrow keys (+ RTL), PageDown / PageUp, Home / End

Each bullet names *what a reviewer will find in the diff* and, where it is not obvious,
what it is for (`making it focusable`, `announced by screen readers`). It is not a summary
of a file.

**Group related edits into one bullet.** Three CSS files that got the same rule are one
bullet, not three. Ten renamed call sites are one bullet.

**Sub-bullets carry detail, not more changes.** Indent under the bullet they qualify:

> - Added `KeyboardMixin` and logic for Arrow keys (+ RTL), PageDown / PageUp, Home / End
>   - Arrow keys use a hardcoded default step of 16px, no custom step for now
>   - PageDown / PageUp keys use 10% as a step (evaluated using available size)

**Tests and dev pages get their own bullets** when they are part of the deliverable:

> - Added DOM snapshot tests and typings tests
> - Added playground dev page with various states

**Cap at ~10 bullets.** Past that, either the bullets are too granular or the PR should be
split — say which, in chat, rather than padding the list.

### Rewrites

- ❌ This PR adds a new mixin that handles keyboard events for the splitter element.
- ✅ Added `KeyboardMixin` and logic for Arrow keys (+ RTL), PageDown / PageUp, Home / End

- ❌ Updated `vaadin-split-layout.js`
- ✅ Added CSS to apply `outline` on the splitter if `focus-ring` is set (base styles and Lumo)

- ❌ Various improvements to accessibility
- ✅ Added `aria-valuemin`, `aria-valuemax` and `aria-valuenow` announced by screen readers

- ❌ Added tests / Added more tests / Updated snapshots — three bullets
- ✅ Added DOM snapshot tests and typings tests — one bullet

## Prose

Allowed, but rationed. One short paragraph, above the bullets, and only when the bullets
cannot carry the reasoning:

- the root cause of a bug that the fix does not make obvious;
- an alternative a reviewer would otherwise suggest, and why it lost;
- a constraint that shaped the approach.

> The original implementation used `touch-action: none` on `<div part="thumb">`. This
> wasn't changed when updating the implementation to use native `<input type="range">` as
> an interactive element. This PR fixes that.

Three sentences. If a paragraph is running past five, it is explaining the diff rather
than the decision.

## How to test

- Numbered. Each step is one action.
- Step 1 names a page that exists: `dev/<component>.html` in web-components, the
  `*-integration-tests/src/main/java/**/<Name>View.java` view in flow-components. Check the
  file is really there before naming it.
- The last step states what should happen — `the field is shown as invalid`,
  `nothing is selected`. A run with no observable result is not a test.
- Keyboard keys as `<kbd>Enter</kbd>`.
- A preamble line for a prerequisite: `On a touch device, or with touch emulation:`.

> 1. Focus a required, empty `vaadin-multi-select-combo-box` and open the overlay.
> 2. Scroll the list by touch — the field is shown as invalid.
> 3. Type `apple` and press <kbd>Enter</kbd> — nothing is selected.

## Anti-patterns

Each of these has shown up in a real PR body:

- **The essay.** Four paragraphs walking through the mechanism when six bullets would do.
  Long prose belongs in a code comment or the linked issue.
- **A bullet per file.** The diff already lists the files.
- **Restating the diff.** `Changed the return value of X from A to B` adds nothing a
  reviewer does not see. Say what it means: `X now reports … so Y no longer runs twice`.
- **Leftover template text.** `Fixes # (issue)`, `Please list all relevant dependencies…`,
  the `## Checklist` block, unticked `- [ ] Bugfix` boxes.
- **Empty sections.** A `## How to test` heading with `N/A` under it. Delete the heading.
- **The AI footer.** `🤖 Generated with Claude Code` and every variant.
- **Vague verbs.** `Improved`, `Enhanced`, `Refactored for clarity`, `Various fixes`.
  Name the change.
- **Hedging.** `Should now work`, `This might fix`. If it is uncertain, say what is
  untested, in the description, once.
