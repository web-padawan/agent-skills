# Comment guidelines

This file tells you how to word findings so that they land well as PR comments. Read it before
you write any finding text.

## Shape

Every comment is a [Conventional Comment](https://conventionalcomments.org). Render it from the
label, decorations, claim and fix of the frozen list
([`../../../references/severity.md`](../../../references/severity.md), *Rendering*):

```
**<label> (<decorations>):** <subject — the frozen claim, one sentence>

<discussion — the one-line fix, then how it was verified when that is not obvious>
```

- The label line is bold, ends with a colon, and is the first line of the message.
  `post-comment.sh` refuses a message that does not start this way.
- The subject is the claim as triage froze it. Do not soften or expand it here.
- The discussion is one short paragraph at most. It gives the fix, and the verification when a
  reader would otherwise have to trust you (`git show <base>` read, the suite searched, the
  browsers reproduced in). Leave no trace of how you found the finding.
- Do not write `[A]` / `[B]` / `[C]` in a posted comment. The decoration already says `blocking`
  or `non-blocking`. The letters are the vocabulary of the plugin.
- A `question` has a subject that ends in a question mark. Its discussion says what you checked
  and what you could not check. It never asserts the thing that you could not verify.
- A routed `question (a11y|design|semver|flow)` names the owner or the test, for example the
  AT × browser matrix, the theme, or the Flow API. It draws no conclusion.
- Give `praise` once per review, on a decision that the author actually made. Examples: a clean
  boundary with named consumers, or a regression test that fails without the fix. Never give
  generic praise.

## Rules

- Use backticks for all code elements (for example `@Override`, `toString()`): annotations, method names, variables, classes, and so on. This prevents accidental user mentions.
- Be clear about **why** the issue is a problem.
- Be brief. Write at most 1 paragraph per finding.
- Explicitly state the scenarios or environments where the issue arises.
- Use a matter-of-fact tone, as a helpful reviewer, not an accusatory one.
- Write for quick comprehension without close reading.

## Summary comment

Offer it at the gate. Never post it by default. Make three moves, in this order:

1. One specific thing done well. Use the `praise` finding, if one exists.
2. A census by label: "2 issues, 3 suggestions, 1 question".
3. What clearing the findings earns: "then this is ready to merge" / "the questions decide the verdict".

## Good and bad comment examples

**Good comments** (specific, actionable, about added code):

- `**issue (logic, blocking):** The null check on line 26 does not prevent the NPE — `userId` can still be null after validation.`
- `**issue (behavior, blocking):** The new SQL query on line 45 is vulnerable to injection.` with `Use a parameterized query.` as the discussion.
- `**suggestion (tests, non-blocking):** The empty-array path of the added loop has no test.` with the scenario named in the discussion.
- `**question (impact):** Does `removeAll()` still reach the guard the fix restored? I could not find a caller that exercises it.`

**Bad comments** (vague, redundant, or about already-added code):

- "Consider adding a public field" (when diff shows a public field is already being added)
- "You should add null checking here" (when the diff already shows null checking being added)
- "This naming is wrong... actually it's correct" (self-contradictory)
- `**issue (blocking):** This might leak the listener.` (an unverified claim posted as an issue, so it is a `question`)
- Any suggestion to implement something already shown as added in the diff
