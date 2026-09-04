# Severity — A / B / C

One rubric for every review skill in this plugin. Agents **propose** a tier; the
invoking skill's triage assigns the final one. Agent-proposed tiers run high.

- **A — critical, must fix before merge.** Wrong behavior, regression, a test that lets a
  real bug through, a public API mistake that ships permanently, lint or test failure, an
  a11y or security break, a convention violation a reviewer would block on.
- **B — should fix soon, a follow-up PR is fine.** Real but not merge-blocking: technical
  debt, coverage gaps away from the core behavior, naming or structure that will cost
  later, "this should be split" recommendations.
- **C — opinionated / taste.** Style, comment noise, member ordering, phrasing,
  micro-simplifications, subjective structure preferences.

**Tie-breaker between A and B:** can a follow-up PR fix this without a breaking change or
a user-visible bug? No → **A**.

**Verification caps the tier:** a finding whose key claim triage could not verify is **B**
at most, with the unverified part named in the claim. Impact decides the tier only once
the claim is confirmed.

## Type-aware tiering

The change type shifts where the A line sits. Apply on top of the rubric:

- **feature** — anything in the new public surface a later fix could not correct without a
  breaking change is A: naming, defaults, event or data shape, missing a11y wiring. A
  stated requirement with no implementation is A. Internal debt stays B.
- **fix** — a symptom-only fix is A. A missing or non-failing regression test is A. The same
  bug left in place elsewhere (blast radius) is A when the sibling is released, B when it is
  not reachable yet. A fix that reverses a behavior an existing test asserts on purpose is A:
  it questions the diff, not a line of it.
- **refactor** — any unexplained observable behavior change is A, including a weakened or
  deleted assertion in an existing test. New public API in a refactor is at least B and
  belongs in a separate PR.
- **chore** — nothing is A unless CI would fail.

### Tests findings vs the type-aware line

A tests finding can read as both "lets a real bug through" (A) and "coverage gap away from the
core" (B). The type-aware line wins, except when the unpinned path is what the branch exists
to deliver — then A (on a **fix**, always). Tie-break: pinned anywhere else (another suite,
another theme) → B. A stale-but-passing baseline is B when regenerating it is the whole fix,
but the report must still say the committed baseline does not match the code.

## Slop and comments

Comment noise is C. A comment that is actively **wrong** about the code is B — it will
mislead the next reader.

## Deep-block severities

The change pass's boundary and impact blocks propose their tier by two rules; apply them
literally, nothing else discriminates as sharply:

- **Boundary / api** — a promise that cannot be walked back without a breaking change *and*
  has consumers is A, always. `Consumers: none yet` drops it to B: an unreleased boundary is
  still cheap to move.
- **Impact** — A when a propagation path reaches released behavior with no test on it. B when
  the path is internal or test-covered. C when the ripple is cosmetic.

## Two rules that ride with the rubric into every agent's context

Copy both verbatim into the shared context file:

> **Report, don't self-censor.** Every candidate with a nameable failure scenario or
> concrete cost goes in your report — `unverified` when you cannot verify it. Triage
> verifies and dedups; a finder that silently drops half-believed candidates bypasses
> triage and is the dominant cause of misses.
>
> **C findings are wanted.** The PR-side CI review deliberately drops low-value findings;
> a local review is where nits surface, judged by the author at zero round-trip cost.

What a skill **does** with a tier is the skill's own business: `self-review` reports every
tier, `pr-review`'s triage filter decides which ones are worth a line comment.

## Rendering — Conventional Comments

The tier is the plugin's internal severity. Whatever a human reads — a PR comment, a
follow-up line, a summary — renders it as a [Conventional Comment](https://conventionalcomments.org):
`<label> (<decorations>): <subject>` and then the discussion. Triage assigns the label once,
at step 5.6 of [`pipeline.md`](pipeline.md), and freezes it in the canonical list beside the
tier and category; nothing downstream picks a label from the tier again.

| Frozen list | Label | Decorations |
| --- | --- | --- |
| confirmed A | `issue` | `(<category>, blocking)` |
| confirmed B, wrong behavior exists | `issue` | `(<category>, non-blocking)` |
| confirmed B, improvement only | `suggestion` | `(<category>, non-blocking)` |
| confirmed B or C, the one-line fix is the whole change | `todo` | `(<category>)` |
| confirmed C | `nitpick` | none — non-blocking by nature |
| any tier, key claim `unverified` | `question` | `(<category>)` |
| routed to a human — AT verdict, design intent, semver call, Flow parity | `question` | `(a11y)` · `(design)` · `(semver)` · `(flow)` |
| a process step, not a code change — a `.d.ts` entry, a dev page, a companion PR | `chore` | `(blocking)` when merge depends on it |
| a concern that pre-dates the diff, worth a follow-up issue | `thought` | none |
| one per review, on something real | `praise` | none |

Rules that ride with the table:

- **Closed vocabulary.** The labels above; the twelve pipeline categories as the first
  decoration; `a11y` / `design` / `semver` / `flow` on a routed question; `blocking`,
  `non-blocking`, `if-minor`. Nothing else, and never more than two decorations.
- **`issue` versus `suggestion` versus `nitpick` on a B or C** is the cascade test: does the
  finding change what a downstream consumer gets, or is it how you would have written it?
  The former is an `issue` or `suggestion`; the latter is a `nitpick`.
- **A `question` is worded as one.** The subject asks, the discussion says what was checked
  and what could not be. An unverified claim never posts as an assertion.
- **A routed `question` names the owner or the test**: the AT × browser matrix, the theme to
  check, the Flow API it must match. It concludes nothing.
- **`if-minor`** only on a B `suggestion` whose fix could balloon past its one-line
  description; otherwise `non-blocking`.
- **Every `issue` pairs with its fix**: the frozen list's one-line fix is the discussion.
- **One `praise`, never false.** The change pass's clean deep block is the usual source: a
  boundary that came back `NO FINDINGS` with named consumers is checkable praise.
- The tier letters stay in chat, the findings report and the review record; a PR reader sees
  the label and decoration, which say the same thing in words they already know.

`adversarial-review`'s buckets sit on the same rows: 🔴 High is `issue (blocking)`, 🟠 Medium
is `issue` or `suggestion (non-blocking)`, 🟡 Low is `nitpick`, ✅ Done well is `praise`.
