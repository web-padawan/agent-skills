# Screening verdicts

`scripts/pr-screen.sh` prints the screening facts and a `verdict_hint` from a fixed table.
The plan quotes them under `screening:`. The hint is a proposal, and the reviewer picks at the
gate.

## The verdicts

| Verdict | Means | Default gate option |
| --- | --- | --- |
| take | a code review is worth it now | `Full review`, or `Quick review` on scale trivial |
| review | review, but first confirm the bug on the base | `Full review` |
| decide | the team must decide before a code review is worth it | `Draft a reply` |
| decline | the PR duplicates or conflicts with team work | `Draft a reply` |
| redirect | a better location or mechanism exists | set at triage, step 5 |

## The hint table

| Fact in the plan | Hint | Label for the reply |
| --- | --- | --- |
| `behavior-altering` | decide | `question (semver)` |
| `feature-no-ac` | decide | `question (design)` |
| `low-impact` and `reach_max` 3 or more | decide | `question (design)` |
| `a11y` and `reach_max` 3 or more | decide | `question (a11y)` |
| `untriaged` or `self-filed` | review | `question` |
| none of these | take | none |

`feature-no-ac` and `self-filed` apply only to a contributor. For a team author, pr-screen.sh
prints them in `skipped_flags:`, and they do not change the hint.

Why each row:

- A behavior change in a minor release is a semver call. #12974 changed the host `display`.
  An issue label, a `type!:` title or a `BREAKING CHANGE:` footer in the body sets the flag.
  For a title or a footer, pr-screen.sh also prints `breaking_marker:`.
- The PR template of web-components asks the author to discuss a feature in an issue with
  acceptance criteria first. #12970 had no such issue. A team author takes a feature from the
  backlog. flow-components #10523 got a false `decide` before the flag was limited.
- A Low-impact issue rarely justifies a change to a module that many packages import.
  #12976 changed the PositionMixin of 10 packages. #13316 changed the OverlayMixin of 17.
- An a11y change in a shared module needs a test with a screen reader, which no pass runs.
- An untriaged or self-filed issue has no team confirmation of the bug. A team author who
  files an issue is that confirmation.

## Correct the hint

The table reads only labels, markers and counts. Correct the verdict when a fact outside the
table decides:

- **decline**: a team PR, a team branch or an assignee on the same issue. The linked issue
  in the context file lists the PRs that reference it.
- **decide**: the body or the issue thread shows that a maintainer asked for a discussion.
- **take**: a decide row fired, but a maintainer already agreed on the issue. Quote the comment.

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
