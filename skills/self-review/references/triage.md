# Phases 3–4 — Triage, classification, approval gate

## Phase 3 — Triage (still read-only)

For every finding from phases 1–2:

1. **Verify it against the code.** Agents produce false positives. A finding you cannot confirm is `accepted` with a one-line reason and never reaches the gate.
2. **Dedup.** Same file, line and claim from several agents = one finding; keep the clearest wording and note which categories raised it.
3. **Assign the final tier** (A/B/C per analysis.md), overriding the agent's proposal. Apply the tie-breaker: can a follow-up PR fix it without a breaking change or a user-visible bug?
4. **Write the intended fix** as one line, so the gate decides about known changes rather than vague concerns.

Make no edits in this phase, including "obvious" ones.

## Phase 4 — Approval gate

First in chat, compact and scannable — the full detail belongs in the report:

```
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
- A **deferred A** finding is a legitimate choice, not an error: apply nothing, and the phase-7 verdict becomes *needs more work*. Say so at the gate so the choice is informed.
