# Writing style: Simplified Technical English

This rule applies to every markdown file that you write or edit in this repository.
That includes `SKILL.md` files, agent definitions, references, templates, `README.md` and
`CLAUDE.md`. It does not apply to chat replies.

The criteria are in `references/writing.md`. `CLAUDE.md` imports that file, so the criteria
load in every session. If a changed file is not in the exempt list below, run
`scripts/prose-check.sh` on it. Change the text at each `ban` hit.

## Exempt text

- Text inside fenced code blocks, including printed prompts and commands.
- Table cells. Write them as fragments, but obey the word rules.
- The frontmatter `description` field. It follows the trigger conventions in `skills/authoring-skills/references/descriptions.md`.
- Quoted examples that show good or bad output. These files are examples in full:
  - `references/comment-guidelines.md`
  - `skills/work-summary/assets/TEMPLATE.md`
- Text that a skill prints to the user, even outside a fenced block.
- `docs/retrospective.md`. It is a historical record.
- `references/banned-patterns.md`. It lists the patterns that `scripts/prose-check.sh` rejects.

The check skips code, headings, table rows, quote lines and the frontmatter. To exempt one
other line, add `<!-- prose-ok -->` at its end.

## Existing text

- Every tracked markdown file obeys this rule, except the exempt text above.
- When you edit a paragraph, keep it at this standard. Do not add a sentence that breaks a rule.
- Files in `agents/` and `references/` are tuned prompts. A rewrite can change review behavior. Rewrite one file per change, keep the meaning, and run the skill once on a known PR after the change.
- The plan script copies marked blocks from `references/` into the shared context file. Keep the `<!-- block:name -->` markers intact.
