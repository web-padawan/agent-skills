# Severity — A / B / C

One rubric for every review skill in this plugin. Agents **propose** a tier. The triage of the
invoking skill assigns the final one. Agent-proposed tiers run high.

The script `scripts/review-plan.sh` copies the rubric block below (`<!-- block:rubric -->`)
into every context file. Edit the block here, never in a skill or an agent definition.

<!-- block:rubric -->
- **A: critical, must fix before merge.** Wrong behavior, a regression, a test that lets a
  real bug through, or a public API mistake that ships permanently. Also a lint or test
  failure, an a11y or security break, or a convention violation that a reviewer would block.
- **B: should fix soon, a follow-up PR is fine.** Real but not merge-blocking. Technical
  debt, coverage gaps away from the core behavior, naming or structure that will cost
  later, "this should be split" recommendations.
- **C: opinionated / taste.** Style, comment noise, member ordering, phrasing,
  micro-simplifications, subjective structure preferences.

**Tie-breaker between A and B:** can a follow-up PR fix this without a breaking change or
a user-visible bug? No → **A**.

**The tie-breaker never overrides an explicit A below.** It settles findings that the rubric
leaves between the two tiers. It does not settle findings that a type-aware rule already named.
A follow-up PR can always fix a released sibling. If the tie-breaker applied there, it would
delete the blast-radius rule. Where the two disagree, the specific rule wins and the claim
says why.

**Verification caps the tier:** a finding whose key claim triage could not verify is **B**
at most. Name the unverified part in the claim. Impact decides the tier only after triage
confirms the claim.

**CI is authoritative on a PR scope.** The `ci:` digest of the plan settles lint, test and
visual-baseline state for the head. A green check means that no pass may report that failure.
No pass should re-run the command locally to prove one. A prettier or test run that contradicts
a green check is a local-environment finding, not a PR finding.

A failing or pending check is the reverse. A red lint or test check is **A**, with the check
named in the claim. A pending check caps any claim that depends on it at **B**. When the plan
says that CI is unavailable, lint and test state is unknown, not clean.

## Type-aware tiering

The change type shifts where the A line sits. Apply these rules on top of the rubric:

- **feature**: anything in the new public surface that a later fix could not correct without a
  breaking change is A. That includes naming, defaults, event or data shape, and missing a11y
  wiring. A stated requirement with no implementation is A. Internal debt stays B.
- **fix**: a symptom-only fix is A. A missing or non-failing regression test is A. The same
  bug left in place elsewhere (blast radius) is A when the sibling is released. It is B when
  the sibling is not reachable yet. A fix that reverses a behavior that an existing test
  asserts on purpose is A. It questions the diff, not a line of it.
- **refactor**: any unexplained observable behavior change is A. That includes a weakened or
  deleted assertion in an existing test. New public API in a refactor is at least B and
  belongs in a separate PR.
- **chore**: nothing is A unless CI would fail.
<!-- /block -->

### Tests findings vs the type-aware line

A tests finding can read as both "lets a real bug through" (A) and "coverage gap away from the
core" (B). The type-aware line wins, except when the unpinned path is what the branch exists
to deliver. In that case the tier is A (on a **fix**, always). Tie-break: pinned anywhere else
(another suite, another theme) → B. A stale-but-passing baseline is B when the whole fix is to
regenerate it. The report must still say that the committed baseline does not match the code.

## Slop and comments

Comment noise is C. A comment that is actively **wrong** about the code is B. It will mislead
the next reader.

## Deep-block severities

The boundary and impact blocks of the change pass propose their tier by two rules. Apply the
rules literally, because nothing else discriminates as sharply:

- **Boundary / api**: a promise that a later change cannot retract without a breaking change
  *and* that has consumers is A, always. `Consumers: none yet` drops it to B. An unreleased
  boundary is still cheap to move.
- **Impact**: A when a propagation path reaches released behavior with no test on it. B when
  the path is internal or test-covered. C when the ripple is cosmetic.

## What a skill does with a tier

The plan script copies the report rule and the mode-variant C rule into every skeleton. Both
rules are in [`skeleton-blocks.md`](skeleton-blocks.md). The rubric block above is the one
piece of this file that travels too.

Each skill decides what it **does** with a tier. `self-review` reports every tier. The triage
filter of `pr-review` decides which ones are worth a line comment.

## Rendering — Conventional Comments

The tier is the internal severity of the plugin. A PR comment, a follow-up line, a summary, or
anything else that a human reads renders the tier as a
[Conventional Comment](https://conventionalcomments.org). The form is
`<label> (<decorations>): <subject>` and then the discussion. Triage assigns the label once, at
step 5.7 of [`pipeline.md`](pipeline.md). Triage freezes the label in the canonical list beside
the tier and category. Nothing downstream picks a label from the tier again.

| Frozen list | Label | Decorations |
| --- | --- | --- |
| confirmed A | `issue` | `(<category>, blocking)` |
| confirmed B, wrong behavior exists | `issue` | `(<category>, non-blocking)` |
| confirmed B, improvement only | `suggestion` | `(<category>, non-blocking)` |
| confirmed B or C, the one-line fix is the whole change | `todo` | `(<category>)` |
| confirmed C | `nitpick` | none, non-blocking by nature |
| any tier, key claim `unverified` | `question` | `(<category>)` |
| routed to a human: AT verdict, design intent, semver call, Flow parity | `question` | `(a11y)` · `(design)` · `(semver)` · `(flow)` |
| a process step, not a code change: a `.d.ts` entry, a dev page, a companion PR | `chore` | `(blocking)` when merge depends on it |
| a concern that pre-dates the diff, worth a follow-up issue | `thought` | none |
| one per review, on something real | `praise` | none |

Rules that accompany the table:

- **Closed vocabulary.** The labels above. The twelve pipeline categories as the first
  decoration. `a11y` / `design` / `semver` / `flow` on a routed question. `blocking`,
  `non-blocking`, `if-minor`. Nothing else, and never more than two decorations.
- **`issue` versus `suggestion` versus `nitpick` on a B or C** is the cascade test: does the
  finding change what a downstream consumer gets, or is it only how you prefer to write it?
  The former is an `issue` or `suggestion`. The latter is a `nitpick`.
- **A `question` is worded as one.** The subject asks. The discussion says what you checked and
  what you could not check. An unverified claim never posts as an assertion.
- **A routed `question` names the owner or the test**: the AT × browser matrix, the theme to
  check, the Flow API that it must match. It concludes nothing.
- **`if-minor`** only on a B `suggestion` whose fix could balloon past its one-line
  description. Otherwise `non-blocking`.
- **Every `issue` pairs with its fix**: the one-line fix from the frozen list is the discussion.
- **One `praise`, never false.** Verify it like a finding. The clean deep block of the change
  pass is the usual source. A boundary that returned `NO FINDINGS` with named consumers is
  checkable praise.
- The tier letters stay in chat, the findings report and the review record. A PR reader sees
  the label and decoration. Those say the same thing in words that the reader already knows.

The groups of `adversarial-review` sit on the same rows: 🔴 High is `issue (blocking)`,
🟠 Medium is `issue` or `suggestion (non-blocking)`, 🟡 Low is `nitpick`, ✅ Done well is `praise`.
