# Writing the `description` (the discovery trigger)

When a session starts, the agent builds a listing of every skill's
`description` and scans it to decide *"is there a skill for this request?"* So
the `description` is **not a summary — it is a description of when to trigger
the skill.** Write it for the model, not for humans. This is the single
highest-leverage field in a skill: a great body behind a summary-style
description never fires.

Skills with `disable-model-invocation: true` are never auto-fired, but their
descriptions still carry two jobs: the human scanning the skill list picks by
them, and the boundary clause against sibling skills lives in them. Hold them
to the same standard.

## The four properties of a good description

### 1. Lead with the trigger surface
Pack in the literal verbs, nouns, and phrases a user would actually type.

- **`mutation-coverage`** embeds the vocabulary of the request:
  > "Find source lines and expressions no test asserts on via mutation testing
  > (line-removal by default, Stryker on request), then close each gap with a
  > test that fails when the code is broken."
  The concrete nouns (*mutation testing, Stryker, test, gap*) cover how people
  phrase the request.

### 2. Enumerate situations, not mechanics
List the kinds of request it covers — breadth here is deliberate so many
phrasings match.

- **`arch-review`** lists the questions it answers rather than how it works:
  > "Use when asked whether a change is architecturally safe, what a new API
  > commits to, or what a change's blast radius is."
  A user who types "what does this new property commit us to?" matches even
  though they never said "boundary review".

### 3. State the boundary when a sibling could also match
This repo has five review skills; without boundary clauses they would collide
on every "review this" prompt. Each one names what it is *not* for:

- **`self-review`** — your own branch before opening/updating a PR; not for
  reviewing someone else's PR.
- **`guided-review`** — an interactive walkthrough of someone else's PR;
  read-only, never posts.
- **`adversarial-review`** — one skeptical pass, one summary comment posted.
- **`pr-review`** — a full rubric pass posting inline line comments.

Without those clauses each would over-trigger on the others' prompts.

### 4. Third-person present, no fluff
Well-written skills open with a present-tense verb phrase ("Review a GitHub
pull request…", "Author a new agent skill…"). No "This skill will help you…"
preamble — it wastes the listing budget.

## Worked before / after

### Example A — summary → trigger (under-triggering fix)

❌ **Before (summary):**
> `description: A tool for checking test quality.`

Problems: no trigger words a user types, no situations, reads like docs. A
prompt "find code no test asserts on" may not match "checking test quality".

✅ **After (trigger-shaped, the real `mutation-coverage`):**
> `description: Find source lines and expressions no test asserts on via
> mutation testing (line-removal by default, Stryker on request), then close
> each gap with a test that fails when the code is broken. Scopes to a file, a
> package, or the branch diff, and estimates runtime before mutating.`

Now the verbs and the coverage vocabulary match how the request is phrased.

### Example B — too broad → bounded (over-triggering fix)

❌ **Before (over-broad):**
> `description: Reviews code changes and posts feedback.`

This fires on *any* review request — including your own unpushed branch, which
a PR-comment skill cannot handle.

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

A user asking "is this API change safe to ship?" won't match "runs three
review agents".

✅ **After (situation enumeration):**
> `description: Deep-review a change through three lenses — architectural
> shape, boundary/API promise, and change impact. Use when asked whether a
> change is architecturally safe, what a new API commits to, what a change's
> blast radius is, or before making a breaking change.`

## The litmus / trigger test (do this before shipping)

1. Write **3–5 prompts that SHOULD fire the skill** and **2–3 that should NOT.**
2. Read **only the `description`** (not the body) and predict, for each prompt,
   whether it fires.
3. If your predictions don't match your intent, the description is wrong — fix
   it before touching the body.
   - Misses on should-fire prompts → add the missing literal trigger phrases.
   - Hits on should-not prompts → add/tighten a boundary clause.
4. Re-run until predictions are correct.

> Rule of thumb: if you can't predict which prompts fire it by reading only the
> description, neither can the agent.
