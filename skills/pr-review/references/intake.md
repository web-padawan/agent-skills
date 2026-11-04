# Intake verdicts

`scripts/pr-intake.sh` prints the intake facts and a `verdict_hint` from a fixed table.
The plan quotes them under `intake:`. The hint is a proposal. The maintainer picks at the
gate. The skill never approves, and it never closes a PR.

## The verdicts

| Verdict | Means | Default gate option |
| --- | --- | --- |
| take | a code review is worth it now | `Full review`, or `Quick review` on scale trivial |
| review | review, but first confirm the bug on the base | `Full review` |
| decide | the team must decide before a code review is worth it | `Draft a reply` |
| decline | the PR duplicates or conflicts with team work | `Draft a reply` |
| redirect | a better location or mechanism exists | set after the passes, at step 6 |

## The hint table

| Fact in the plan | Hint | Label for the reply |
| --- | --- | --- |
| `behavior-altering` | decide | `question (semver)` |
| `feature-no-ac` | decide | `question (design)` |
| `low-impact` and `reach_max` 3 or more | decide | `question (design)` |
| `a11y` and `reach_max` 3 or more | decide | `question (a11y)` |
| `untriaged` or `self-filed` | review | `question` |
| none of these | take | none |

Why each row:

- A behavior change in a minor release is a semver call. #12974 changed the host `display`.
  An issue label, a `type!:` title or a `BREAKING CHANGE:` footer in the body sets the flag.
  For a title or a footer, the intake also prints `breaking_marker:`.
- The PR template of web-components asks for a feature to be discussed in an issue with
  acceptance criteria first. #12970 had no such issue.
- A Low-impact issue rarely pays for a change to a module that many packages import.
  #12976 changed the PositionMixin of 10 packages. #13316 changed the OverlayMixin of 17.
- An a11y change in a shared module needs a screen reader verdict, which no pass gives.
- An untriaged or self-filed issue has no team confirmation of the bug.

## Correct the hint

The table reads labels and counts. Correct the verdict when a fact outside the table decides:

- **decline**: a team PR, a team branch or an assignee on the same issue. The linked issue
  in the context file lists the PRs that reference it.
- **decide**: the body or the issue thread shows that a maintainer asked for a discussion.
- **take**: a decide row fired, but a maintainer already agreed on the issue. Quote the comment.

Say in one clause why you corrected the hint.

## Claims of the body

Agent-written bodies claim much. Nine of 11 fork PRs in the corpus claimed that the new test
fails without the fix. Give each checkable claim one status:

- `ci`: a check of the plan answers it.
- `static`: a read of the diff answers it. Name what you read.
- `run`: only a test run answers it. On a fork PR the review runs nothing, so the claim stays
  unverified and can only reach the PR as a `question`.
- `contradicted`: the plan or the diff says otherwise. Example: the body of #13316 says that
  the snapshot run ends with 2 failed tests. A contradicted claim is a finding.
