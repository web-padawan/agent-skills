# Present findings and gate (step 4)

Read [`../../../references/comment-guidelines.md`](../../../references/comment-guidelines.md) first. Open with
two or three sentences on what the PR does, the goal and the mechanism. Then give the structured
review. Render each finding from the frozen list in its Conventional Comments shape. Show the
tier in chat only:

```
## Review: <PR title> (#<number>)

<2–3 sentences: what the PR does and how.>

**Verdict**: Looks good / Needs attention
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

Every finding carries its decoration. A confirmed B where wrong behavior exists is
`issue (<category>, non-blocking)`, not a bare `issue (<category>)`. `praise` and `nitpick`
take no decoration, and `praise` takes no tier. The rendering table in severity.md is the full
set.

The **Dropped at triage** line stays a count and a reason class. The per-finding detail is what
the report in Q2 adds over this chat summary. If you list the dropped findings here, that report
becomes redundant and the offer pointless.

The census line under the verdict counts only findings that are not `already raised`. If
the plan said `existing_comments: none`, omit the **Already on the PR** block.

Give `Needs attention` whenever any `issue` exists, blocking or not. An `issue` says that wrong
behavior exists. `Looks good` over an `issue` reads as a clean bill of health that the review
did not give. Give `Looks good` only when every finding is `suggestion`, `question`, `nitpick`,
`thought` or `praise`. In that case, say explicitly that the code looks good.

Say which findings are `summary-only` (pipeline.md §5.6) before the gate. They never post
inline. `Yes — post all` and `All, plus a summary comment` post them as general comments.
`Only blocking issues` posts them only when their decoration is `blocking`.

Then ask a single `AskUserQuestion` with two questions. **Never post comments without
confirmation.** Drop an option that would post nothing. That includes `Only blocking issues`
when the only blocking finding is `already raised`.

- **Q1, header `Post`**: "Post these as comments on the PR?" with the options `Yes — post all`,
  `Only blocking issues`, `All, plus a summary comment` and `No — chat only`. The summary
  comment is the three-move general comment in comment-guidelines.md. `Only blocking issues`
  posts the `issue (…, blocking)` and `chore (blocking)` lines and nothing else.
  `Yes — post all` and `All, plus a summary comment` post the `contradicts` lines as replies in
  their threads. Never post `confirms` lines, because agreement is not a comment.
- **Q2, header `Report`**: "Write the full review report?" with the options `Yes — write it`
  and `No`. The report goes to `<scratchpad>/pr-<number>-REVIEW.md`. It contains the summary,
  the verdict, and every triaged finding with its tier, label and category. That includes
  the findings that the filter in step 3 kept off the PR, marked `not posted`. The report is a
  record for the reviewer only. Never commit or post it.
