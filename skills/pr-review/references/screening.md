# Screening verdicts

`scripts/pr-screen.sh` prints the screening facts, a `verdict_hint` and one `verdict_reason`
line per rule that fired, for example `behavior-altering -> question (semver)`. The label
after the arrow is the label of the reply. The plan quotes them under `screening:`. The hint
is a proposal, and the reviewer picks at the gate.

## The verdicts

| Verdict | Means | Default gate option |
| --- | --- | --- |
| take | a code review is worth it now | `Full review`, or `Quick review` on scale trivial |
| review | review, but first confirm the bug on the base | `Full review` |
| decide | the team must decide before a code review is worth it | `Draft a reply` |
| decline | the PR duplicates or conflicts with team work | `Draft a reply` |
| redirect | a better location or mechanism exists | set at Triage |

A rule reads a label, a marker or a count. A `type!:` title or a `BREAKING CHANGE:` footer
sets `behavior-altering`, and the script prints `breaking_marker:`. For a team author, the
script prints the contributor rules in `skipped_flags:`, and they do not change the hint.
The evidence behind each rule is in `docs/rationale.md`.

## Correct the hint

The rules read only labels, markers and counts. Correct the verdict when a fact outside the
rules decides:

- **decline**: a team PR, a team branch or an assignee on the same issue. The linked issue
  in the context file lists the PRs that reference it.
- **decide**: the body or the issue thread shows that a maintainer asked for a discussion.
- **take**: a decide rule fired, but a maintainer already agreed on the issue. Quote the comment.

Say in one clause why you corrected the hint.

## Claims of the body

Bodies that an agent wrote make many claims. Nine of 11 fork PRs in the test corpus claimed
that the new test fails without the fix. Give each checkable claim one status:

- `ci`: a check of the plan answers it.
- `static`: a read of the diff answers it. Name what you read.
- `run`: only a test run answers it. On a fork PR, the review runs nothing. The claim stays
  unverified and can reach the PR only as a `question`.
- `contradicted`: the plan or the diff says otherwise. Example: the body of #13316 says that
  the snapshot run ends with 2 failed tests. A contradicted claim is a finding.
