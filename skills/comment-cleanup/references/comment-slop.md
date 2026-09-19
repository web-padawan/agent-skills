# Comment slop: smells, recipes and the manifest check

This reference names the comment smells that a cleanup run meets, and it gives one recipe
for each. The policy in [`../../../references/comments.md`](../../../references/comments.md)
decides the verdict. This file decides the new text. Classify the smell before you edit,
then run one pass per smell.

## Smell table

Each example comes from the `time-picker` run of 2026-09-19.

| Smell | Example | Verdict | Recipe |
| --- | --- | --- | --- |
| Narration | `// Commit value based on focused index` | DROP | delete the line |
| Shape in prose | `Returning Object in the format {hours,...}` | REWRITE | `@param {T \| undefined} obj Time object` and `@return {number} milliseconds` |
| Repeated tag | a prose line above `@return {boolean} True if ...` | DROP | delete the prose line, keep the tag |
| Copy of public docs | a private docblock with the table that the class JSDoc has | DROP | delete, name the public copy in the report |
| History wrapper | `is a trick to prevent Safari AutoFill ... <closed link>` | REWRITE | keep the reason, delete the link |
| Shorthand link | `see #6397` | REWRITE | the full URL when the issue is open, delete when closed |
| Misplaced why | `// Open dropdown only when clicking label` inside `_onHostClick` | REWRITE | move into the leading line of the override docblock |
| Typo in a mandated line | `to handle Escape pres..` | REWRITE | fix the typo, change nothing else |
| Filler | `for better UX experience`, `i.e.`, `e.g.` | REWRITE | the shortest form, sync the `.d.ts` when the member is public |

## Recipes for a docblock rewrite

Apply these rules when a REWRITE produces or changes a tag.

- Write one `@param` per parameter and one `@return` when the member returns a value.
- Give a tag description as a noun phrase without a final period, for example `Time object`.
- Verify the nullability of each type from three places: the callers, a `?.` in the body,
  and the sibling `.d.ts`. Write `{X | undefined}` when `undefined` flows in.
- When a type comes from a sibling module, add one `@typedef` after the imports:
  `@typedef {import('./x-helper.js').T} T`.
- Keep the visibility tag as the last tag of the docblock.
- Keep the leading line that the conventions document mandates for an override. Match the
  form that the file uses. Count both forms in the repository when the file mixes them.
- Check the state of a linked issue with `gh issue view <number> --json state`.

## Style facts for web-components

These counts come from `packages/*/src/*.js` on 2026-09-19. They are measurements, not
rules. Count again when a rewrite depends on one of them.

| Fact | Count |
| --- | --- |
| private or protected methods with parameters and a bare `/** @private */` | 873 |
| the same, with a docblock that holds `@param` tags | 413 |
| the same, with a docblock that holds prose and no `@param` | 127 |
| `Override method inherited from` leading lines | 89 |
| `Override method from` leading lines | 68 |
| `Override an event listener from` leading lines | 32 |
| `@param` descriptions without a final period | 129 |
| `@param` descriptions with a final period | 36 |
| `@return` tags without a description | 308 |
| `@return` tags with a description | 58 |
| `{X \| undefined}` tags | 40 |
| `{?X}` tags | 8 |
| `@typedef {import(...)}` declarations | 2 |

A REWRITE moves a prose docblock into the tagged form. It never moves a docblock into the
bare form. `CONVENTIONS.md` requires a visibility tag on every non-public member and the
override leading line. `tsconfig.json` includes only `.ts` files, so no compiler checks a
JSDoc type in a `.js` file.

## Manifest check

Run this check when the repository generates an API manifest from JSDoc. In web-components
the command is `yarn release:cem` and the output is `packages/<name>/custom-elements.json`.
Identical output proves that no shipped documentation changed.

1. Copy each edited source file to the scratch directory.
2. Restore the edited files with `git checkout -- <paths>`.
3. Generate the manifest. Copy `packages/<name>/custom-elements.json` to the scratch
   directory as `before.json`.
4. Copy the edited files back from the scratch directory.
5. Generate the manifest again. Copy the output as `after.json`.
6. Run `diff before.json after.json`. Empty output passes the check.

The manifest file is ignored by git, so the check leaves the tree as it found it.
