# Comment policy — DROP, REWRITE or RETAIN

This file holds the one policy for every skill and agent in this plugin that judges a
comment. The code pass of the review pipeline reports against it. The `comment-cleanup` skill
edits against it. Edit the block below. Never edit a copy of it.

`scripts/review-plan.sh` copies the block into the context file of a review whose diff
touches a comment. The `comment-cleanup` skill reads this file directly.

<!-- block:comment-policy -->
Judge each comment that the diff ADDS. Give it one of three verdicts. DROP deletes the
block. REWRITE keeps the block and changes its text. RETAIN keeps the text as it is.

| The comment describes | Verdict |
| --- | --- |
| behavior of the code that the code already shows | DROP |
| a historical change, a past decision record, a closed ticket, a changelog note | DROP |
| a border condition that the code already expresses | DROP |
| an invariant, a precondition or a postcondition that the type declaration states | DROP |
| a repetition of a pattern, for example `same as above` | DROP |
| a prose line that repeats a tag in the same docblock | DROP |
| anything that no row covers | DROP |
| the shape of a parameter or of a return value, in prose | REWRITE to `@param` and `@return` tags |
| what an override does differently, in an inline comment inside the override | REWRITE into the leading line of the docblock |
| a reason wrapped in history, a `#NNNN` shorthand, a typo, or spare words | REWRITE to the shortest form |
| the contract of a private or a protected member | RETAIN |
| why the code cannot do the thing another way | RETAIN |
| an invariant, a precondition or a postcondition that no type declaration states | RETAIN |

Five carve-outs outrank the table:

- A rule in the conventions document of the repository outranks every row. Read its JSDoc
  chapter before the first verdict. A leading line that the chapter mandates is a RETAIN.
- A docblock on a private or a protected member is never a DROP. The visibility tag stays.
  The prose becomes tags, or it stays as the contract.
- A full link to an **open** issue that explains a current workaround is a RETAIN. A closed
  issue is a REWRITE. Keep the reason and delete the link. Never use the `#` shorthand.
- A docblock on a **public** member is never a DROP. The type declarations, the web types
  and the documentation site include its text. A REWRITE of it edits the sibling `.d.ts` too.
- Every docblock tag is a RETAIN, for example `@param`, `@return`, `@type`, `@attr` and
  `@fires`. A directive is not a comment. Keep `eslint-disable`, `prettier-ignore`,
  `@ts-expect-error`, `c8 ignore`, `istanbul ignore` and a license header.

Rewrite each REWRITE comment:

- Remove the historical reason.
- Use as few words as possible.
- Use the name that the code uses for each concept.
- Match the wording form that the file already uses. Before you say that one form is wrong,
  count both forms in the repository.
<!-- /block -->
