# Present findings and gate

Read [`../../../references/comment-guidelines.md`](../../../references/comment-guidelines.md)
first. Then run `${CLAUDE_PLUGIN_ROOT}/scripts/pr-refresh.sh --context <context file>`
and act on each `action:` line. An author can push after the plan ran, and a bot can add
threads. Then give the review below. Render each finding of the frozen list (the findings
that triage kept) as a Conventional Comment:

```
## Review: <PR title> (#<number>)

<2–3 sentences: what the PR does and how.>

**Result**: Looks good / Needs attention
<census by label: N issues (K blocking), N suggestions, N questions, N nitpicks>

### Findings

[A] `path/to/file.ext:42`
**issue (behavior, blocking):** <the frozen claim>
<the one-line fix; verification when not obvious>
Failing test in `<test file>`: <the test method, in a fenced block>

[B] `path/to/other.ext:17`
**issue (behavior, non-blocking):** <the frozen claim>
<the one-line fix>

[B] `path/to/third.ext:88`
**question (behavior):** <the frozen claim, worded as a question?>
<what was checked, and what could not be>

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

Show each failing test in full, because the reviewer posts it. If Triage gave a `behavior`,
`fix`, `logic` or `impact` issue no test, give the reason in one line. Example:
`no test: the head is not checked out`.

The findings file of Triage holds the detail of each dropped finding. Do not list them in
the chat.

The census line under the result counts only findings that are not `already raised` and not
`dropped`. If
the plan said `existing_comments: none`, omit the **Already on the PR** block.

Give `Needs attention` whenever any `issue` exists, blocking or not. An `issue` says that wrong
behavior exists. `Looks good` above an `issue` tells the reader that the review found no
problem, which is false. Give `Looks good` only when every finding is `suggestion`,
`question`, `nitpick` or `thought`. In that case, say explicitly that the code looks
good.

Before the post gate, say which findings are `summary-only` (pipeline.md §5.6).
`Yes — post all` puts them in the review body.

On a fork PR, put `One summary review` first. The author then gets one list of changes.

Send the review as text in a message of its own. Ask the post question in the next message.
The open question dialog can cover the text above it, and a message can lose its text. So the
question text carries the census and the label and anchor of each finding that can post:

```
Post these as comments on the PR? 1 issue (1 blocking), 1 nitpick:
issue (behavior, blocking) `Foo.java:42`; nitpick `Bar.java:17`.
```

Ask it as one `AskUserQuestion` with the header `Post`. Drop an option that would post
nothing. The options:

- `Yes — post all`: one review, with a thread per finding and the summary of
  comment-guidelines.md in its body.
- `One summary review`: every finding in the review body, blocking first (`--body-only`).
- `No — chat only`.

With each option, the script posts a `contradicts` or `not fixed` finding as a reply into its
thread. It never posts a `confirms` finding, because agreement is not a comment.
