# Phase 3 — Triage and fixes

## Triage (before touching anything)

For each finding from phases 1–2:
1. Verify it against the actual code — agents produce false positives.
2. Label it:
   - `fix` — real and worth fixing now; apply the fix.
   - `accepted` — false positive, out of scope for this branch, or deliberate choice. Requires a one-line reason. Splittability recommendations are usually `accepted` + surfaced in the verdict.
3. Never fix by weakening a test to make it pass — if a `direction` finding says the test pins wrong behavior, fix the behavior or the expectation to match the *intent*.

## Fix order

1. Apply all `fix`-labeled findings.
2. `Skill(simplify)` — record what it changed as `simplification` findings marked `fixed`; record suggestions you reject as `accepted` + reason.
3. `Skill(oh-my-claudecode:ai-slop-cleaner)` — runs after simplify so it sees final shapes; record its changes as `slop` findings.
4. Comment policy pass (below) — record removals as `slop` findings.

## Comment policy

- Remove comments from code and tests except JSDoc and comments stating a constraint the code cannot show (workaround for a browser bug with link, non-obvious ordering requirement).
- Comments that narrate what the next line does, restate the diff, or justify the change to a reviewer: always remove.
- CSS files: trim every comment to at most 1 line; remove decorative section banners.

## Gate

After all fixes, the repo's lint and the affected tests must pass — see the command map in phase 0 of SKILL.md (`yarn lint` + `yarn test --group <name>` per affected package in vaadin/web-components). Fix regressions before proceeding. Then commit once, per finalize.md — phase 4 needs a clean tree to mutate against.
