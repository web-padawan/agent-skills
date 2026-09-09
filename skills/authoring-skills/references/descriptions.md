# Writing the `description` (the discovery trigger)

When a session starts, the agent builds a listing of the `description` of every skill.
The agent scans that listing to decide if a skill exists for the request. So the
`description` is **not a summary but a description of when to trigger the skill.** Write
it for the model, not for humans. This is the field with the highest leverage in a skill.
A great body behind a summary-style description never fires.

Skills with `disable-model-invocation: true` never fire automatically. Their descriptions
still have two jobs. The human who scans the skill list picks a skill by its description.
The boundary clause against sibling skills also lives in the description. Hold these
descriptions to the same standard.

## The four properties of a good description

### 1. Lead with the trigger surface
Include the literal verbs, nouns, and phrases that a user would type.

- **`mutation-coverage`** embeds the vocabulary of the request:
  > "Find source lines and expressions no test asserts on via mutation testing
  > (line-removal by default, Stryker on request), then close each gap with a
  > test that fails when the code is broken."

  The concrete nouns (*mutation testing, Stryker, test, gap*) cover how people phrase
  the request.

### 2. Enumerate situations, not mechanics
List the kinds of request that the skill covers. Breadth here is deliberate, so that
many phrasings match.

- **`pr-description`** lists the requests that it answers rather than how it works:
  > "Use when asked to write a PR description, fill in the PR template,
  > describe this branch for a PR, update or improve the PR body, or add a
  > how-to-test section."

  A user who types "fill in the template for this branch" matches even though the user
  never said "PR description".

### 3. State the boundary when a sibling could also match
This repo has four review skills. Without boundary clauses they would collide on every
"review this" prompt. Each one names what it is *not* for:

- **`self-review`**: your own branch before you open or update a PR. Not for a review of
  a PR from someone else.
- **`guided-review`**: an interactive walkthrough of a PR from someone else. Read-only,
  never posts.
- **`adversarial-review`**: one skeptical pass, one posted summary comment.
- **`pr-review`**: a full rubric pass that posts inline line comments.

Without those clauses each skill would over-trigger on the prompts of the other skills.

### 4. Third-person present, no fluff
Well-written skills open with a present-tense verb phrase. Examples are
"Review a GitHub pull request…" and "Author a new agent skill…". Do not add a
"This skill will help you…" preamble. It wastes the listing budget.

## Worked before / after

### Example A — summary → trigger (under-triggering fix)

❌ **Before (summary):**
> `description: A tool for checking test quality.`

Problems: no trigger words that a user types, no situations, and it reads like docs. A
prompt "find code no test asserts on" may not match "checking test quality".

✅ **After (trigger-shaped, the real `mutation-coverage`):**
> `description: Find source lines and expressions no test asserts on via
> mutation testing (line-removal by default, Stryker on request), then close
> each gap with a test that fails when the code is broken. Scopes to a file, a
> package, or the branch diff, and estimates runtime before mutating.`

Now the verbs and the coverage vocabulary match the phrasing of the request.

### Example B — too broad → bounded (over-triggering fix)

❌ **Before (over-broad):**
> `description: Reviews code changes and posts feedback.`

This fires on *any* review request, which includes your own unpushed branch. A PR-comment
skill cannot handle that branch.

✅ **After (bounded):**
> `description: Review a GitHub pull request against a rubric and post findings
> as inline comments after confirmation. Use for a full reviewer pass on
> someone else's PR. Not for a single summary comment (adversarial-review), an
> interactive walkthrough (guided-review), or your own branch before it has a
> PR (self-review).`

The explicit "not for…" clause stops the false positives.

### Example C — mechanics → situations (breadth fix)

❌ **Before (mechanics):**
> `description: Runs three review agents with structured field contracts.`

A user who asks "is this API change safe to ship?" will not match "runs three review
agents".

✅ **After (situation enumeration):**
> `description: Self-review the current branch before opening or updating a
> PR — scope, behavior and compatibility, fix correctness, boundary and impact
> of the significant changes, code quality, tests. Use on your own branch; not
> for reviewing someone else's PR.`

## The litmus / trigger test (do this before shipping)

1. Write **3 to 5 prompts that SHOULD fire the skill** and **2 to 3 that should NOT.**
2. Read **only the `description`** (not the body). Predict for each prompt whether it
   fires.
3. If your predictions do not match your intent, the description is wrong. Fix it before
   you touch the body.
   - Misses on should-fire prompts: add the missing literal trigger phrases.
   - Hits on should-not prompts: add or tighten a boundary clause.
4. Repeat until the predictions are correct.

> Rule of thumb: if you cannot predict from the description alone which prompts fire the
> skill, the agent cannot either.
