# Comment policy — DROP or RETAIN

One policy for every skill and agent in this plugin that judges a comment. The code pass of
the review pipeline reports against it. The `comment-cleanup` skill edits against it. Edit
the block below. Never edit a copy of it.

`scripts/review-plan.sh` copies the block into the context file of a review whose diff
touches a comment. The skill reads this file directly.

<!-- block:comment-policy -->
Judge each comment that the diff ADDS. A comment that the table drops is noise. The code
already says it, or the code is the wrong place to say it.

| The comment describes | Verdict |
| --- | --- |
| behavior of the code that the code already shows | DROP |
| a historical change, a past decision record, a closed ticket, a changelog note | DROP |
| a border condition that the code already expresses | DROP |
| an invariant, a precondition or a postcondition that the type declaration states | DROP |
| a repetition of a pattern, for example `same as above` | DROP |
| the prose of a docblock on a private or a protected member | DROP |
| anything that no row above covers | DROP |
| why the code cannot do the thing another way | RETAIN |
| an invariant, a precondition or a postcondition that no type declaration states | RETAIN |

Four carve-outs outrank the table:

- A full link to an **open** issue that explains a current workaround is a RETAIN. It gives
  the reason that the code cannot do the thing another way. A closed issue and a decision
  record are DROP. Never use the `#` shorthand for an issue.
- A docblock on a **public** member is a RETAIN. Its text ships in the type declarations, in
  the web types and on the documentation site.
- Every docblock tag is a RETAIN, for example `@param`, `@return`, `@type`, `@attr` and
  `@fires`. A tag is API data, not prose.
- A directive is not a comment. Keep `eslint-disable`, `prettier-ignore`, `@ts-expect-error`,
  `c8 ignore`, `istanbul ignore` and a license header.

Rewrite each RETAIN comment:

- Remove the historical reason.
- Use as few words as possible.
- Use the name that the code uses for each concept.
<!-- /block -->
