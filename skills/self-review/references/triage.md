# Stages 2–3 — Triage, classification, gate

## Stage 2 — Triage (read-only, like everything else)

First, if you have not already: run the **roll call** from arch-review's `delivery.md`. Triaging before the roll call means silently triaging a subset — a pass whose report was lost looks exactly like a pass with nothing to say.

For every finding from stage 1 (and the `--deep` lens run, when one happened):

1. **Verify it against the code.** Agents produce false positives. A finding you cannot confirm is `accepted` with a one-line reason and never reaches the gate.
2. **Dedup.** Same file, line and claim from several agents = one finding; keep the clearest wording and note which categories raised it.
3. **Correlate the deep-review lenses** — only when `--deep` ran. The three lenses landing on the same change from different angles is signal, not noise: merge them into one finding and mark it `[3-lens]` / `[2-lens]`, per arch-review's own triage rules. The narrative blocks still go into the report in full — only the finding lines merge.
4. **Assign the final tier** (A/B/C per analysis.md), overriding the agent's proposal. Apply the tie-breaker: can a follow-up PR fix it without a breaking change or a user-visible bug?
5. **Write the suggested fix** as one line. This skill changes nothing, so that line is the entire actionable output — it is what the user acts on. Make it concrete and specific to the file and line. A report full of "consider refactoring this" is worthless; "move the listener removal into `disconnectedCallback`" is not.

### Wording — claims and suggested fixes

The gate listing and the report reuse these lines verbatim, so fix the wording here, once:

- Every identifier, method, type, and compared literal in backticks — `resolveLabel`, `"No matching option"`.
- Plain developer words; no invented labels ("foot-gun", "split-brain").
- One short sentence per claim: keep the one detail that makes the problem concrete, drop call chains and mechanism retellings.

### Type-aware tiering

The change type shifts where the A line sits — apply these on top of the rubric:

- **feature** — anything in the new public surface that a later fix could not correct without a breaking change is A: naming, defaults, event or data shape, missing a11y wiring. A stated requirement with no implementation is A. Internal debt stays B.
- **fix** — a symptom-only fix is A. A missing or non-failing regression test is A. The same bug left in place elsewhere (blast radius) is A when the sibling is released, B when it is not reachable yet. A contradicted premise is A and does not reach this stage at all: the run stopped at the premise check, because triaging the implementation of a fix the project did not ask for produces findings about code that is about to be deleted.
- **refactor** — any unexplained observable behavior change is A, including a weakened or deleted assertion in an existing test. New public API in a refactor is at least B and belongs in a separate PR — and is exactly the case to point at `/agent-skills:arch-review` in the report.
- **chore** — nothing here is A unless CI would fail.

## Stage 3 — Gate

First in chat, compact and scannable — the full detail belongs in the report:

```
Profile: refactor — signal: branch prefix `refactor/`
Premise: sound — #9239 review kept the filter guard   (fix profile only)

A (must fix before merge) — 2
  packages/foo/src/foo.js:42 — <claim> → <suggested fix>
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
