# Phases 3–4 — Triage, classification, approval gate

## Phase 3 — Triage (still read-only)

First, if you have not already: run the **Delivery check** in analysis.md. Triaging before the roll call means silently triaging a subset — a pass whose report was lost looks exactly like a pass with nothing to say.

For every finding from phases 1–2:

1. **Verify it against the code.** Agents produce false positives. A finding you cannot confirm is `accepted` with a one-line reason and never reaches the gate.
2. **Dedup.** Same file, line and claim from several agents = one finding; keep the clearest wording and note which categories raised it.
3. **Assign the final tier** (A/B/C per analysis.md), overriding the agent's proposal. Apply the tie-breaker: can a follow-up PR fix it without a breaking change or a user-visible bug?
4. **Write the intended fix** as one line, so the gate decides about known changes rather than vague concerns.

Make no edits in this phase, including "obvious" ones.

### Type-aware tiering

The change type shifts where the A line sits — apply these on top of the rubric:

- **feature** — anything in the new public surface that a later fix could not correct without a breaking change is A: naming, defaults, event or data shape, missing a11y wiring. A stated requirement with no implementation is A. Internal debt stays B.
- **fix** — a symptom-only fix is A. A missing or non-failing regression test is A. The same bug left in place elsewhere (blast radius) is A when the sibling is released, B when it is not reachable yet.
- **refactor** — any unexplained observable behavior change is A, including a weakened or deleted assertion in an existing test. New public API in a refactor is at least B and belongs in a separate PR.
- **chore** — nothing here is A unless CI would fail.

## Phase 4 — Approval gate

First in chat, compact and scannable — the full detail belongs in the report:

```
Profile: feature (arch pass on) — signal: PR title `feat:`

A (must fix before merge) — 2
  packages/foo/src/foo.js:42 — <claim> → <intended fix>
  …
B (follow-up is fine) — 3
  …
C (taste) — 5
  …
```

Then a single `AskUserQuestion` with two questions:

**Q1 — header `Apply now`**: "Which findings should I apply to the working tree now?"
- `A + B` *(Recommended)* — everything real; taste findings left alone
- `A only` — merge blockers only
- `A + B + C` — including the stylistic ones
- `None — report only` — change nothing, just write the report

**Q2 — header `Coverage`**: "May the coverage check write breaking tests for lines no test pins?"
- `Yes — add tests for survivors` *(Recommended)*
- `No — report survivors only`
- `Skip the coverage check` — fastest; no mutants are run

Rules:

- No edits before this gate, and none outside what it approves.
- A custom answer ("Other") wins over the preset options — apply exactly what it names.
- Real findings that are not approved become `deferred` in the report and are listed under Follow-ups.
- Nothing to apply (no findings, or only ones already `accepted`) → ask Q2 alone.
- Profile has no mutant budget (**chore**) → ask Q1 alone.
- On a **fix**, say at the gate that skipping the coverage check also skips the regression-test verification — that is the one check a bug fix most needs.
- A **deferred A** finding is a legitimate choice, not an error: apply nothing, and the phase-7 verdict becomes *needs more work*. Say so at the gate so the choice is informed.
