# Screening

Read this file only when the plan says `fork: true`, or when the PR author is not on the
team (`pr_author: <login> (contributor)` in the screening lines). Skip it for a team PR.

## Screening card

Add the card to the explanation of the PR.

```
- Issue: #<n>, <labels that matter>, <team or contributor>, <age> | none linked
- Flags: <each issue_flags entry of the plan, with what it means for this PR> | none
- Reach: <the consumers that the diff_facts lines name, the widest first> | none named
- Claims: <one line per checkable claim of the body, with its status>
```

## Flags

`scripts/pr-screen.sh` prints the screening facts, and the plan quotes them under
`screening:`. A flag is a fact for the reviewer. The reviewer decides at the gate whether a
code review is worth it now. Each flag reads a label, a marker or the author:

| Flag | Means |
| --- | --- |
| `behavior-altering` | a breaking label, a `type!:` title or a `BREAKING CHANGE:` footer: a semver call |
| `feature-no-ac` | a feature of a contributor, and the issue has no acceptance criteria |
| `low-impact` | the issue has a low impact label. Compare it with the `reach` lines |
| `a11y` | the issue has an accessibility label. No pass runs a screen reader. Compare it with the `reach` lines |
| `untriaged`, `self-filed` | no team member confirmed the bug |

The label rules and the team allowlist come from the config that `screening_config:` names.
Without a config, only the generic rules apply. For a team author, the script prints the
contributor flags in `skipped_flags:`. The evidence behind each flag is in
`docs/lessons.md`.

The flags read only labels, markers and the author. When another fact matters at the gate,
add a line to the card:

- a team PR, a team branch or an assignee on the same issue
- a maintainer who asked for a discussion in the body or in the issue thread
- a maintainer who already agreed on the issue. Quote the comment.

## Claims of the body

Bodies that an agent wrote make many claims. Nine of 11 fork PRs in the test corpus claimed
that the new test fails without the fix. Give each checkable claim one status:

- `ci`: a check of the plan answers it.
- `static`: a read of the diff answers it. Name what you read.
- `run`: only a test run answers it. On a fork PR, the review runs nothing. The claim stays
  unverified and can reach the PR only as a `question`.
- `contradicted`: the plan or the diff says otherwise. Example: the body says that the test
  run ends with 2 failed tests, and the `ci:` line of the plan shows a green test check. A
  contradicted claim is a finding.
