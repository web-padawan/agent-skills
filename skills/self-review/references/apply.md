# Phase 5 — Apply approved fixes

Only what the phase-4 gate approved, nothing else. An improvement you spot while editing is a new finding for the report, not a free edit.

1. Apply in tier order **A → B → C**, so a taste edit never obscures a real fix in the diff.
2. Approved `simplification` and `slop` findings are applied as **targeted edits at their file:line**. Do not re-run `Skill(simplify)` or the slop cleaner in applying mode — they would change more than was approved.
3. **Never fix by weakening a test.** If an `intent` or `behavior` finding says a test pins wrong behavior, fix the behavior, or fix the expectation to match the stated intent — never relax the assertion to make it pass.
4. Gate: lint and the affected tests must pass (phase-0 command map). A failure you introduced here is an A finding — fix it before continuing, and record it.
5. **Stage exactly the paths you changed**: `git add <path> <path> …`. Never `git add -A` or `git add .` — that would sweep the user's unrelated untracked files into the index.
6. Verify `git diff --name-only` is empty: everything you changed is staged. Phase 6 depends on this — its restore step reads the index.

Do not commit, amend, or push. The user commits.

Record each applied finding as `fixed` and each approved-but-impossible one as `deferred` with the reason.
