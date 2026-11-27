# Banned patterns

`scripts/prose-check.sh` reads the table in this file. An agent does not read this file. The
script prints the row of each hit, so the agent sees the replacement at the hit.

The rules that need judgment are in [`writing.md`](writing.md). This file holds only the
patterns that a script can find.

## Columns

- **Pattern**: a plain pattern matches the start of a word, without regard to case. For example,
  `utiliz` matches `utilize` and `utilizing`. A pattern between two slashes is a Python regular
  expression. Write `\|` for a `|` in a cell.
- **Tier**: `ban` means that the text must change. `flag` marks a smell. Change a `flag` hit only
  when the word adds no fact.
- **Use instead**: the replacement, or the action.
- **Scope**: `prose` applies to markdown, for example an issue draft. `comment` applies to a code
  comment. `all` applies to both.

## Sources

- A phrase that opens or closes a text matches only at the start of a sentence, before a comma.
- The words and the phrases come from the GitLab skill `natural-writing-style` and from the
  emphasis examples of the Simplified Technical English rules.
- The punctuation rows and the Latin abbreviation rows enforce the Simplified Technical English
  rules in prose. A code comment follows the form of its file, so these rows do not apply to
  it. In the comments of web-components, `e.g.` occurs on 130 lines and `for example` on 20.
- The `comment` rows come from a count over the comments of web-components on 2026-11-27.
  The counts were `ensure` 65, `in order to` 32, `make sure` 25, `note that` 20, `properly` 18
  and `correctly` 8.

Add a row when a real draft or a real comment used the pattern.

<!-- block:patterns -->
| Pattern | Tier | Use instead | Scope |
| --- | --- | --- | --- |
| `delve` | ban | examine | all |
| `utiliz` | ban | use | all |
| `leverag` | ban | use | all |
| `facilitat` | ban | help, allow | all |
| `streamlin` | ban | simplify | all |
| `endeavo` | ban | try, work | all |
| `bolster` | ban | strengthen | all |
| `multifaceted` | ban | name the parts | all |
| `pivotal` | ban | important, or delete it | all |
| `synerg` | ban | state the effect | all |
| `paradigm` | ban | model, pattern | all |
| `holistic` | ban | complete, or delete it | all |
| `seamless` | ban | state the behavior | all |
| `robust` | ban | state what it survives | all |
| `powerful` | ban | state what it does | all |
| `crucial` | ban | required, or delete it | all |
| `truly` | ban | delete it | all |
| `comprehensive` | ban | complete, full | all |
| `cutting-edge` | ban | new, latest | all |
| `innovative` | ban | new | all |
| `empower` | ban | allow, let | all |
| `unleash` | ban | allow | all |
| `best practice` | flag | name the practice | all |
| `stakeholder` | flag | name the group: users, developers, maintainers | prose |
| `in order to` | ban | to | all |
| `due to the fact that` | ban | because | all |
| `it is important to note` | ban | state the fact | all |
| `it is worth noting` | ban | state the fact | all |
| `it is worth mentioning` | ban | state the fact | all |
| `it should be noted` | ban | state the fact | all |
| `a wide range of` | ban | many, or name them | all |
| `pave the way` | ban | allow | all |
| `unlock the potential` | ban | allow | all |
| `feel free to` | ban | delete it, give the instruction | all |
| `hope this helps` | ban | delete it | prose |
| `thanks so much` | ban | delete it | prose |
| `when it comes to` | ban | for, or start with the subject | prose |
| `/(?:^\|(?<=[.:?] ))(in conclusion\|to summarize\|in summary\|moving forward\|at the end of the day),/` | ban | delete it, end with the next step | prose |
| `/\b(could\|might\|may) (potentially\|possibly)\b/` | ban | name the condition, or state the fact | all |
| `potentially` | flag | name the condition | all |
| `note that` | flag | state the fact | all |
| `ensure` | flag | name the result, or delete the clause | comment |
| `make sure` | flag | name the result, or delete the clause | comment |
| `properly` | flag | name the behavior | all |
| `correctly` | flag | name the behavior | all |
| `simply` | flag | delete it | all |
| `basically` | flag | delete it | all |
| `essentially` | flag | delete it | all |
| `/\bthere are (two\|three\|four\|five\|several) \w+/` | flag | delete the count, show the items | prose |
| `/\be\.g\./` | ban | for example | prose |
| `/\bi\.e\./` | ban | that is | prose |
| `/\betc\./` | ban | name the items | prose |
| `/[—–]/` | ban | a comma, or two sentences | prose |
| `/;(?!\S)/` | ban | a period, or two sentences | prose |
| `/\b\w+n't\b/` | ban | the full form, for example `do not` | prose |
| `/\b(it\|that\|there\|what\|here\|let\|who)'s\b/` | ban | the full form, for example `it is` | prose |
| `/\b\w+'(re\|ll\|ve\|m\|d)\b/` | ban | the full form, for example `you will` | prose |
| `/[“”‘’]/` | ban | a straight quote | prose |
| `/·/` | ban | a comma | prose |
| `/!(?!\S)/` | ban | a period | prose |
| `/[\U0001F000-\U0001FAFF\u2300-\u23FF\u25A0-\u27BF\u2B00-\u2BFF\uFE0F]/` | ban | delete it | prose |
<!-- /block -->
