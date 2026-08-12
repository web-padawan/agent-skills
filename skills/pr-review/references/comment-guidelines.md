# Comment guidelines

How to word findings so they land well as PR comments. Read before writing any finding text.

## Rules

- Use backticks for all code elements (e.g., `@Override`, `toString()`): annotations, method names, variables, classes, etc. This prevents accidental user mentions.
- Be clear about **why** the issue is a problem.
- Be brief — at most 1 paragraph per finding.
- Explicitly state scenarios/environments where the issue arises.
- Use a matter-of-fact tone — helpful reviewer, not accusatory.
- Write for quick comprehension without close reading.

## Good and bad comment examples

**Good comments** (specific, actionable, about added code):

- "This null check on line 26 won't prevent the NPE because `userId` can still be null after validation"
- "The new SQL query on line 45 is vulnerable to injection — use parameterized queries"
- "This added loop will be infinite when the array is empty due to the counter logic"

**Bad comments** (vague, redundant, or about already-added code):

- "Consider adding a public field" (when diff shows a public field is already being added)
- "You should add null checking here" (when the diff already shows null checking being added)
- "This naming is wrong... actually it's correct" (self-contradictory)
- Any suggestion to implement something already shown as added in the diff
