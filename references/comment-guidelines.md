# Comment guidelines

This file tells you how to word findings so that they land well as PR comments. Read it before
you write any finding text.

## Shape

Every comment is a [Conventional Comment](https://conventionalcomments.org). Render it from the
label, decorations, claim and fix of the frozen list
([`severity.md`](severity.md), *Rendering*):

```
**<label> (<decorations>):** <subject — the frozen claim, one sentence>

<discussion — the one-line fix, then how it was verified when that is not obvious>
```

- The label line is bold, ends with a colon, and is the first line of the message.
  `post-comment.sh` refuses a message that does not start this way.
- The subject is the claim as triage froze it. Do not soften or expand it here.
- The discussion is one short paragraph at most. It gives the fix, and the verification when a
  reader would otherwise have to trust you (`git show <base>` read, the suite searched, the
  browsers reproduced in). Leave no trace of how you found the finding.
- Do not write `[A]` / `[B]` / `[C]` in a posted comment. The decoration already says `blocking`
  or `non-blocking`. The letters are the vocabulary of the plugin.
- A `question` has a subject that ends in a question mark. Its discussion says what you checked
  and what you could not check. It never asserts the thing that you could not verify.
- A routed `question (a11y|design|semver|flow)` names the owner or the test, for example the
  AT × browser matrix, the theme, or the Flow API. It draws no conclusion.
- Give `praise` once per review, on a decision that the author actually made. Examples: a clean
  boundary with named consumers, or a regression test that fails without the fix. Never give
  generic praise.

## Rules

- Use backticks for all code elements (for example `@Override`, `toString()`): annotations, method names, variables, classes, and so on. This prevents accidental user mentions.
- Be clear about **why** the issue is a problem.
- Be brief. Write at most 1 paragraph per finding.
- Explicitly state the scenarios or environments where the issue arises.
- Use a matter-of-fact tone, as a helpful reviewer, not an accusatory one.
- Write for quick comprehension without close reading.

## Summary comment

Offer it at the gate. Never post it by default. It goes in the review body
(`post-review.sh --summary`). Make three moves, in this order:

1. One specific thing done well. Use the `praise` finding, if one exists.
2. A census by label: "2 issues, 3 suggestions, 1 question".
3. What clearing the findings earns: "then this is ready to merge" / "the questions decide the verdict".

## Good and bad comment examples

**Good comments** (specific, actionable, about added code):

- `**issue (logic, blocking):** The null check on line 26 does not prevent the NPE — `userId` can still be null after validation.`
- `**issue (behavior, blocking):** The new SQL query on line 45 is vulnerable to injection.` with `Use a parameterized query.` as the discussion.
- `**suggestion (tests, non-blocking):** The empty-array path of the added loop has no test.` with the scenario named in the discussion.
- `**question (impact):** Does `removeAll()` still reach the guard the fix restored? I could not find a caller that exercises it.`

**Bad comments** (vague, redundant, or about already-added code):

- "Consider adding a public field" (when diff shows a public field is already being added)
- "You should add null checking here" (when the diff already shows null checking being added)
- "This naming is wrong... actually it's correct" (self-contradictory)
- `**issue (blocking):** This might leak the listener.` (an unverified claim posted as an issue, so it is a `question`)
- Any suggestion to implement something already shown as added in the diff

## Posting a review with post-review.sh

Post only after the user confirms. Post the findings that the user selected as one review.
Then the author gets one notification, not one for each finding. Call
`${CLAUDE_PLUGIN_ROOT}/scripts/post-review.sh`:

1. Write the selected findings to a JSON file in the scratchpad. Give each finding its
   `file`, its `line` and its `message`. Use `null` for a line or a file that does not apply.
2. If the user chose a summary comment, write its three moves to a markdown file.
3. Run the script once with `--dry-run`. Read the bodies that it prints.
4. Run it again without `--dry-run`.

```bash
post-review.sh --pr <number> --findings <scratchpad>/pr-<number>-post.json \
  [--summary <scratchpad>/pr-<number>-summary.md] [--dry-run]
```

```json
{"findings": [{"file": "path/to/file.ext", "line": 42, "message": "**issue (logic, blocking):** <claim>\n\n<fix>"}]}
```

- The script refuses the whole batch when one message has no valid label.
- Each finding goes on its line. When GitHub refuses the line, the finding goes on the file.
  When GitHub refuses the file, the finding goes in the review body.
- A finding within two lines of an existing thread is skipped. Reply into that thread
  with `post-comment.sh --reply <id>`. Set `"allow_nearby": true` only for a different claim.
- The review body holds an overview line, the summary, a table of all findings and a
  hidden marker with the reviewed head SHA.

## Posting with post-comment.sh

Use `post-comment.sh` for a reply into an existing thread, and for a single comment outside
a review run. Post only after the user confirms. Call the script by its full path,
`${CLAUDE_PLUGIN_ROOT}/scripts/post-comment.sh`. The examples below abbreviate the path.

- The script puts `:robot: AI-generated` above every comment.
- The script refuses a message whose first line is not a bold label from the closed vocabulary
  in [`severity.md`](severity.md) (*Rendering*).
- Use `--no-label` for a plain reply or for the summary comment.
- If GitHub rejects the position, the script posts a labeled general comment.

```bash
# Inline comment on an added/modified line (new side); --line 42:48 for a range
post-comment.sh --pr <number> --file path/to/file.ext --line 42 --message "**issue (behavior, blocking):** <claim>

<fix; verification when not obvious>"

# Removed line (old side)
post-comment.sh --pr <number> --file path/to/file.ext --old-line 10 --message "**question (impact):** ..."

# The summary comment (three moves, no label), and a reply to an existing thread
post-comment.sh --pr <number> --no-label --message "<praise line> <census> <what clearing them earns>"
post-comment.sh --pr <number> --reply <comment-id> --no-label --message "Fixed, thanks."

# A contradiction of an existing thread: a labeled reply, never a new comment on that line
post-comment.sh --pr <number> --reply <comment-id> --message "**question (logic):** <what the review found instead>?

<what was checked>"
```

Do not combine `--line` and `--old-line`. Select the most relevant single line or a narrow range.

The script refuses a positioned comment within two lines of an existing thread on the same file.
It exits with 2 and lists that thread. Reply into that thread instead. If the claim is different,
pass `--allow-nearby`.
