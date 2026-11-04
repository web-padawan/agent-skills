# Present findings and gate (step 6)

Read [`../../../references/comment-guidelines.md`](../../../references/comment-guidelines.md)
first. Then give the review below. Render each finding of the frozen list (the findings that
triage kept) as a Conventional Comment:

```
## Review: <PR title> (#<number>)

<2–3 sentences: what the PR does and how.>

**Result**: Looks good / Needs attention
<census by label: N issues (K blocking), N suggestions, N questions, N nitpicks, praise>

### Findings

[A] `path/to/file.ext:42`
**issue (behavior, blocking):** <the frozen claim>
<the one-line fix; verification when not obvious>

[B] `path/to/other.ext:17`
**issue (behavior, non-blocking):** <the frozen claim>
<the one-line fix>

[B] `path/to/third.ext:88`
**question (behavior):** <the frozen claim, worded as a question?>
<what was checked, and what could not be>

**praise** `path/to/test.ext:12`
<what the author got right — no tier, no decoration, at most one per review>

### Already on the PR

<N> findings match existing threads (<K> bot, <M> human) and are not offered for posting.
confirms: <thread ids, or "path:line by author", comma-separated>
contradicts: <one line each — the thread, and what the review found instead>
not reproduced: <open threads no pass matched, each with your verdict>

### Dropped at triage

<one line: N findings dropped, and the single reason class — pre-existing, unverified,
answered by a green check. Names only, no claims.>
```

Every finding carries its decoration. Example: a confirmed B that shows wrong behavior is
`issue (<category>, non-blocking)`, not a bare `issue (<category>)`. The rendering table in
severity.md gives the full set.

The report of Q2 gives the detail of each dropped finding. A list of them in the chat makes
that report redundant.

The census line under the result counts only findings that are not `already raised`. If
the plan said `existing_comments: none`, omit the **Already on the PR** block.

Give `Needs attention` whenever any `issue` exists, blocking or not. An `issue` says that wrong
behavior exists. `Looks good` above an `issue` tells the reader that the review found no
problem, which is false. Give `Looks good` only when every finding is `suggestion`,
`question`, `nitpick`, `thought` or `praise`. In that case, say explicitly that the code looks
good.

Before the post gate, say which findings are `summary-only` (pipeline.md §5.6).
`Yes — post all` puts them in the review body. `Only blocking issues` posts them
only when their decoration is `blocking`.

On a fork PR, or on a `redirect` verdict, put `One summary review` first. The author then gets
one list of changes, as in *Replies by verdict* of comment-guidelines.md.

Then ask one `AskUserQuestion` with two questions. Drop an option that would post nothing. Example: drop `Only blocking issues`
when the only blocking finding is `already raised`.

- **Q1, header `Post`**: "Post these as comments on the PR?" The options:
  - `Yes — post all`: one review, with a thread per finding and the three-move summary of
    comment-guidelines.md in its body.
  - `One summary review`: every finding in the review body, blocking first.
  - `Only blocking issues`: the `issue (…, blocking)` and `chore (blocking)` lines, and nothing
    else.
  - `No — chat only`.

  `Yes — post all` and `One summary review` post the `contradicts` lines as replies in their
  threads. Never post `confirms` lines, because agreement is not a comment.
- **Q2, header `Report`**: "Write the full review report?" with the options `Yes — write it`
  and `No`. The report goes to `<scratchpad>/pr-<number>-REVIEW.md`. It holds the summary, the
  result, and every triaged finding with its tier, label and category. That includes the
  findings that the filter of step 5 kept off the PR, marked `not posted`. The report is a
  record for the reviewer only. Never commit or post it.
