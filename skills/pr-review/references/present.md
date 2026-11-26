# Present and post

Read [`../../../references/comment-guidelines.md`](../../../references/comment-guidelines.md)
first. Then give the review below. Render each finding of the frozen list as a Conventional
Comment:

```
## Review: <PR title> (#<number>)

<2–3 sentences: what the PR does and how.>

**Result**: Looks good / Needs attention
<census by label: N issues (K blocking), N suggestions, N questions, N nitpicks>

### Findings

[A] `path/to/file.ext:42`
**issue (behavior, blocking):** <the frozen claim>
<the one-line fix; verification when not obvious>

[B] `path/to/third.ext:88`
**question (behavior):** <the frozen claim, worded as a question?>
<what was checked, and what could not be>

### Already on the PR

<N> findings match existing threads (<K> bot, <M> human) and are not offered for posting.
confirms: <thread ids>
contradicts: <one line each: the thread, and what the review found instead>
not reproduced: <open threads that no pass matched, each with your verdict>

### Dropped at triage

<one line: N findings dropped, and the reason classes. Names only, no claims.>
```

- Every finding carries its decorations, per the table of review-rules.md §6.
- The census counts only findings that are not `already raised` and not `dropped`. Omit
  **Already on the PR** when the plan said `existing_comments: none`.
- Give `Needs attention` whenever any `issue` exists, blocking or not. Give `Looks good` only
  when every finding is a `suggestion`, `question`, `nitpick` or `thought`. Then say that the
  code looks good.
- Name the `summary-only` findings. They go in the review body.

## Post question

Send the review as text in a message of its own. Ask the post question in the next message,
as one `AskUserQuestion` with the header `Post`. The open dialog can hide the text above it.
So the question text carries the census, and the label and anchor of each finding that can
post:

```
Post these as comments on the PR? 1 issue (1 blocking), 1 nitpick:
issue (behavior, blocking) `Foo.java:42`; nitpick `Bar.java:17`.
```

The options. Drop an option that would post nothing:

- `Yes — post all`: one review, with a thread per finding.
- `One summary review`: every finding in the review body, blocking first. List it first on a
  fork PR, so that the author gets one list of changes.
- `No — chat only`.

A free answer wins over the options. When it excludes findings, set their status to
`dropped excluded by reviewer`.

## Post

Call `${CLAUDE_PLUGIN_ROOT}/scripts/post-review.sh` with the findings file of Triage and the
`head:` SHA of the plan. Add `--body-only` for `One summary review`.

1. When the reviewer asked for a summary, write what clearing the findings earns to a file,
   and pass it as `--summary`. The script writes the census line itself.
2. Run the script once with `--dry-run`. Read the bodies that it prints.
3. Run it again without `--dry-run`. Give the link of each posted thread and of the review.

The script posts no `confirms` verdict, and posts a `contradicts` or `not fixed` verdict as a
reply into its thread. It refuses the whole batch on a bad label, status or anchor, and when
the head moved and a commented file changed. Then fix the batch, or review the new head. A
finding within two lines of an existing thread is skipped: triage that thread, then set `dup`
on the finding.
