# Stages 3–4 — Triage, classification, gate

## Stage 3 — Triage (read-only, like everything else)

First, if you have not already: run the **Delivery check** in analysis.md. Triaging before the roll call means silently triaging a subset — a pass whose report was lost looks exactly like a pass with nothing to say.

For every finding from stages 1–2:

1. **Verify it against the code.** Agents produce false positives. A finding you cannot confirm is `accepted` with a one-line reason and never reaches the gate.
2. **Dedup.** Same file, line and claim from several agents = one finding; keep the clearest wording and note which categories raised it.
3. **Correlate the deep-review lenses.** The three lenses will land on the same change from different angles — that is signal, not noise. Merge them into one finding and mark it `[3-lens]` when all three raised it, `[2-lens]` for two. A change flagged by architectural, boundary *and* impact is the strongest statement this skill can make; do not let dedup flatten it into an ordinary line. The three narrative blocks still go into the report in full — only the finding lines merge.
4. **Assign the final tier** (A/B/C per analysis.md), overriding the agent's proposal. Apply the tie-breaker: can a follow-up PR fix it without a breaking change or a user-visible bug?
5. **Write the suggested fix** as one line. This skill changes nothing, so that line is the entire actionable output — it is what the user acts on. Make it concrete and specific to the file and line. A report full of "consider refactoring this" is worthless; "move the listener removal into `disconnectedCallback`" is not.

### Type-aware tiering

The change type shifts where the A line sits — apply these on top of the rubric:

- **feature** — anything in the new public surface that a later fix could not correct without a breaking change is A: naming, defaults, event or data shape, missing a11y wiring. A stated requirement with no implementation is A. Internal debt stays B.
- **fix** — a symptom-only fix is A. A missing or non-failing regression test is A. The same bug left in place elsewhere (blast radius) is A when the sibling is released, B when it is not reachable yet.
- **refactor** — any unexplained observable behavior change is A, including a weakened or deleted assertion in an existing test. New public API in a refactor is at least B and belongs in a separate PR — the boundary review will normally have caught it first.
- **chore** — nothing here is A unless CI would fail.

## Stage 4 — Gate

First in chat, compact and scannable — the full detail belongs in the report:

```
Profile: refactor · deep-reviewed 3 of 5 significant changes — signal: branch prefix `refactor/`

A (must fix before merge) — 2
  packages/foo/src/foo.js:42 — <claim> → <suggested fix>   [3-lens]
  …
B (follow-up is fine) — 3
  …
C (taste) — 5
  …
```

**Say this before asking, whenever there is at least one A:** this skill applies nothing, so an A finding cannot be cleared inside a run — the verdict will be *needs more work* regardless of what is chosen here. The gate decides what gets **produced**, not what gets **changed**.

Then a single `AskUserQuestion` with two questions:

**Q1 — header `Report`**: "Write the findings report?"
- `Yes — write FINDINGS.md` *(Recommended)* — name the stage-0 path in the option description
- `No — chat summary only`

**Q2 — header `Coverage`**: "Run the coverage check? It temporarily mutates source lines and restores each one."
- `Yes — run it` *(Recommended)*
- `Skip it`

Rules:

- A custom answer ("Other") wins over the preset options — do exactly what it names.
- Nothing is dropped either way. `No — chat summary only` means the findings are reported in chat instead of a file, not that any of them disappear.
- Nothing to report (no findings, or only ones already `accepted`) → ask Q2 alone.
- Profile has no mutant budget (**chore**), or `--no-coverage` was passed → ask Q1 alone.
- On a **fix**, say at the gate that skipping the coverage check also skips the whole-fix revert — the one check a bug fix most needs, since it is what proves a regression test exists.
