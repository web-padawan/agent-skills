# Fallback — single-context review

Use this fallback only when the plugin agents are unavailable, or when the ANCHORS SHAs stay
unresolved. The second case means that the plan printed `base: unresolved` even after it
fetched `pull/<n>/head`. In every other case, run the pipeline in SKILL.md.

Re-run `${CLAUDE_PLUGIN_ROOT}/scripts/get-pr-context.sh --pr <number>` without `--no-diff`.
That gives you the `=== DIFFS ===` section. If the branch is dirty, follow the `hint:` lines of
the output: ask the user, then pass `--diff-source local` or `--diff-source remote`. Then review
the diff yourself:

- `+` lines are code that the author has already written. Review their quality. Never suggest
  that the author implement them.
- Optimize for recall first. Then validate each finding for precision.
- Cover **correctness** (logic errors, edge cases, off-by-one, races, null/undefined),
  **security** (injection, auth bypass, secrets, unvalidated input, open redirects),
  **maintainability** (unclear naming, excessive complexity, missing error handling, untested
  paths), **performance** (N+1 queries, unnecessary allocations, unbounded loops).
- Apply the filter of SKILL.md step 3 and the tiers of severity.md. Then present per step 4.
  Every finding is `self-run` in the roll call. Say so before the gate.
