# Quick review — one context

Use this path in these cases:

- The reviewer picks `Quick review` at the gate.
- The plugin agents are not available.
- `base` and `head` of the plan stay unresolved after the script fetched `pull/<n>/head`.

Every finding of this path is `self-run` in the roll call. Say so before the post gate.

## Read the diff

Read the production and test diff with the literal SHAs of the plan:
`git diff <base>..<head> -- <prod_files> <test_files>`. For a dirty branch, first follow the
`hint:` lines of `get-pr-context.sh`. On a fork PR, read the post-change files with
`git show <head>:<path>`.

Apply the repo conventions. The plan names the doc in `conventions_doc:`. Read it before
you flag a convention. Do not repeat a point that the context file shows as already made or
addressed.

## Review

`+` lines are code that the author already wrote. Review their quality. Never suggest that the
author implement them. Optimize for recall first, then verify each finding.

Report real issues only. Rank the most serious first:

- **Correctness**: wrong logic, edge cases, null or undefined values, races, off-by-one.
- **Regressions and safety**: behavior changes, security holes, missing error handling,
  performance cliffs.
- **Consumers**: the consumers that the `diff_facts` lines of the plan name.
- **Coverage gaps**: untested branches, or new behavior with no test.
- **Fit**: does the PR follow the established patterns, at the right layer? Flag a touched
  layer that the fix does not need.

Do not report style, naming preferences or formatting. Write any other minor point as a
one-line `nitpick`.

For each finding, give:

- `file:line`
- what is wrong, and why it matters
- the failure scenario or the fix

Read the code around a claim before you assert it. A claim about code outside the hunk names
the line that proves it, the same as `src:` in pipeline.md §3.

## Triage and present

Apply the Triage filter of SKILL.md and the tiers of severity.md. Then continue with Present
and Post.
