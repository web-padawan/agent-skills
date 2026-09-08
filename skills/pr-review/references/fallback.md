# Fallback — single-context review

Used only when the plugin agents are unavailable or the ANCHORS SHAs cannot be resolved (the
plan printed `base: unresolved` even after its `pull/<n>/head` fetch). Everything else runs the
pipeline in SKILL.md.

Re-run `${CLAUDE_PLUGIN_ROOT}/scripts/get-pr-context.sh --pr <number>` without `--no-diff` to
get the `=== DIFFS ===` section — follow its `hint:` lines if the branch is dirty (ask the
user, then `--diff-source local` or `--diff-source remote`) — and review the diff yourself:

- `+` lines are code the author has already written — review their quality, never suggest
  implementing them.
- Optimize for recall first, then validate each finding for precision.
- Cover **correctness** (logic errors, edge cases, off-by-one, races, null/undefined),
  **security** (injection, auth bypass, secrets, unvalidated input, open redirects),
  **maintainability** (unclear naming, excessive complexity, missing error handling, untested
  paths), **performance** (N+1 queries, unnecessary allocations, unbounded loops).
- Apply SKILL.md step 3's filter and severity.md's tiers, then present per step 4. Every
  finding is `self-run` in the roll call — say so before the gate.
