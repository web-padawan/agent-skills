# Quick review — one context

Use this path when the reviewer picks `Quick review` at the gate, or when the plugin agents
are unavailable. Use it also when `base` and `head` of the plan stay unresolved after the
script fetched `pull/<n>/head`. Every finding of this path is `self-run` in the roll call.
Say so before the post gate.

## Read the diff

Read the production and test diff of the plan:
`git diff <base>..<head> -- <prod_files> <test_files>`, with the literal SHAs of the plan.
For a dirty branch, follow the `hint:` lines of `get-pr-context.sh` first. On a fork PR,
read the post-change files with `git show <head>:<path>`. Never check out the head.

Apply the repo conventions. The plan names the doc in `conventions_doc:`. Read it before
you flag a convention. Do not repeat a point that the context file shows as already made or
addressed.

## Review

`+` lines are code that the author already wrote. Review their quality. Never suggest that the
author implement them. Optimize for recall first, then verify each finding.

Focus on genuine issues. Rank the most serious first:

- **Correctness**: wrong logic, edge cases, null or undefined values, races, off-by-one.
- **Regressions and safety**: behavior changes, security holes, missing error handling,
  performance cliffs.
- **Consumers**: the packages in the `reach` lines of the plan, and the Flow counterpart.
- **Coverage gaps**: untested branches, or new behavior with no test.
- **Fit**: does the PR follow the established patterns, at the right layer? Flag a touched
  layer that the fix does not need.

Do not nitpick style, naming preferences or formatting. Mark a minor point as a `nitpick`
in one line.

For each finding, give `file:line`, what is wrong, why it matters, and the failure scenario
or the fix. Read the code around a claim before you assert it. A claim about code outside the
hunk names the line that proves it, the same as `src:` in pipeline.md §3.

## Then

Apply the filter of SKILL.md step 5 and the tiers of severity.md. Then present per step 6.
