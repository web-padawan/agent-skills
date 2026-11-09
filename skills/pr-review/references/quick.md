# Quick review — one context

Use this path in these cases:

- The reviewer picks `Quick review` at the gate.
- The plugin agents are not available.
- `base` and `head` of the plan stay unresolved after the script fetched `pull/<n>/head`.

Every finding of this path is `self-run` in the roll call. Say so before the post gate.

## Read the context file

In this path you are the reviewer, so read the file that the passes read. Read the context
file of the plan once. It holds these parts:

- the diff, inline or as the patch files that it names
- the conventions excerpt, each line with its number in the doc, and the owner rules
- the diff facts, with their `rule:` lines
- the comments already on the PR

Do not run `git diff` and do not open the conventions doc again. Cite a convention as
`src:<doc>:<line>`. Apply each `rule:` line. Do not repeat a point that `## Already on the PR`
shows as already made or addressed.

If the plan wrote no context file, read the diff with the literal SHAs of the plan:
`git diff <base>..<head> -- <prod_files> <test_files>`. For a dirty branch, first follow the
`hint:` lines of `get-pr-context.sh`. On a fork PR, read the post-change files with
`git show <head>:<path>`. Read the `conventions_doc:` and the `owner_rules:` files of the plan before you flag a
convention.

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

Apply the Triage filter of SKILL.md, the tiers of severity.md and the `owner_rules:` file
(pipeline.md §5). Then continue with Present and Post.
