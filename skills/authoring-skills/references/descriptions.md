# Writing the `description` (the discovery trigger)

When a session starts, the agent builds a listing of the `description` of every skill.
The agent scans that listing to decide if a skill exists for the request. So the
`description` must **describe when to trigger the skill.** A summary of the skill does
not work. Write it for the model, not for humans. The `description` does more for
discovery than any other field. A great body behind a summary-style description never
fires.

Skills with `disable-model-invocation: true` never fire automatically. Their descriptions
still have two jobs. The human who scans the skill list picks a skill by its description.
The boundary clause against sibling skills also lives in the description. Hold these
descriptions to the same standard.

## The four properties of a good description

### 1. Lead with the trigger surface
Include the literal verbs, nouns, and phrases that a user would type.

- **`screenshot-diff`** embeds the vocabulary of the request:
  > "Use when a visual baseline changed or is about to change (a Playwright or
  > Chromium bump, a component or theme change), when `yarn test:lumo` /
  > `test:aura` / `test:base` left `failed/` screenshots..."

  The concrete nouns (*baseline, Playwright, failed screenshots*) cover how people phrase
  the request.

### 2. Enumerate situations, not mechanics
List the kinds of request that the skill covers. Breadth here is deliberate, so that
many phrasings match.

- **`work-summary`** lists the requests that it answers rather than how it works:
  > "Use when asked to summarize my work, my PRs or my commits, write a work
  > report, a status update, a monthly or sprint summary, or
  > `"what I did on <component> in <period>"`."

  A user who types "write my status update for September" matches even though the user
  never said "work summary".

### 3. State the boundary when a sibling could also match
This repo has three review skills. Without boundary clauses they would collide on every
"review this" prompt. Each one names what it is *not* for:

- **`self-review`**: your own branch before you open or update a PR. Not for a review of
  a PR from someone else.
- **`guided-review`**: an interactive walkthrough of a PR from someone else. Posts only
  the findings that you select.
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
prompt "why did these screenshots fail" may not match "checking test quality".

✅ **After (trigger-shaped, the real `screenshot-diff`):**
> `description: Classify a visual test screenshot change as sub-pixel
> rendering, transition or animation flakiness, browser update rasterization
> noise, or a real content change. Use when a visual baseline changed or is
> about to change, or when asked to analyze, triage or rank screenshot diffs.`

Now the verbs and the screenshot vocabulary match the phrasing of the request.

### Example B — too broad → bounded (over-triggering fix)

❌ **Before (over-broad):**
> `description: Reviews code changes and posts feedback.`

This fires on *any* review request, which includes your own unpushed branch. A PR-comment
skill cannot handle that branch.

✅ **After (bounded):**
> `description: Review a GitHub pull request against a rubric and post findings
> as inline comments after confirmation. Use for a full reviewer pass on
> someone else's PR. Not for an interactive walkthrough (guided-review), or
> your own branch before it has a PR (self-review).`

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

1. Write 3 to 5 prompts that SHOULD fire the skill and 2 to 3 that should NOT.
2. Read only the `description` (not the body). Predict for each prompt whether it
   fires.
3. If your predictions do not match your intent, the description is wrong. Fix it before
   you touch the body.
   - Misses on should-fire prompts: add the missing literal trigger phrases.
   - Hits on should-not prompts: add or tighten a boundary clause.
4. Repeat until the predictions are correct.

> Rule of thumb: if you cannot predict from the description alone which prompts fire the
> skill, the agent cannot either.
