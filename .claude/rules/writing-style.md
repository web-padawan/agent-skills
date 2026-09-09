# Writing style: Simplified Technical English

This rule applies to every markdown file that you write or edit in this repository.
That includes `SKILL.md` files, agent definitions, references, templates, `README.md` and
`CLAUDE.md`. It does not apply to chat replies.

The rules come from criteria 17 to 58 of
[spec-quality-principles.md](https://github.com/kant13/spec-review/blob/3a2a1d296b92bb0255f67400cd513fb31411abb9/.agents/skills/spec-review/references/spec-quality-principles.md),
an adaptation of ASD-STE100 Issue 9. Criterion 17 replaces the STE dictionary: use familiar
words, and explain an unfamiliar word where you first use it. No word list is enforced.

## Words

- Use one name for each concept in all files. Do not use a synonym for variety.
- Select the shortest name that identifies the object without ambiguity.
- Do not use slang, regional terms, or jargon as technical names.
- Use technical nouns as nouns and technical verbs as verbs.
- Use American English spelling.
- Use no more than three words in a noun group. Write a longer official name in full first, then use a short form.
- Use English words instead of Latin abbreviations. Write `for example`, not `e.g.`
- Use gender-neutral names for roles.

## Sentences

- Use no more than 20 words in an instruction. Use no more than 25 words in a descriptive sentence.
- Count a number, an abbreviation, an identifier, quoted text, hyphenated words, and text in parentheses as one word each.
- Give one instruction in each sentence. Give one topic in each sentence.
- Use the active voice. In a description, use the passive voice only when the actor is unknown.
- Use the imperative for each step in a procedure.
- If the reader must know a condition before a step, put the condition first. Put a comma between the condition and the command.
- Use a verb to tell the reader about an action. Do not hide the action in a noun.
- Do not use phrasal verbs. Write `start`, not `kick off`. Write `configure`, not `set up`.
- Use only these verb forms: infinitive, imperative, simple present, simple past, simple future, and past participle as an adjective.
- Use an `-ing` form only as a technical noun or as a modifier in a technical noun.
- Use full forms instead of contractions.
- Use `that` to mark the start of a dependent clause.
- Check that each pronoun refers to one clear object. If it does not, write the name again.
- Use `with` in one meaning only in a sentence.

## Punctuation

- Do not use semicolons in prose.
- Do not use em-dashes or en-dashes in prose. Write two sentences, or use a comma.
- Use parentheses only for a reference, an identifier, an abbreviation, an explanation of a word, or an alternative.
- Use hyphens to show which words form one unit, for example `read-only`.

## Paragraphs and structure

- Give one topic in each paragraph. Use no more than six sentences in a paragraph.
- Use a vertical list for a set with more than two items or with conditions.
- Use connecting words to show how sentences relate. Use the same words for the same relation.
- Put an instruction in the main text. Use a note only to give information.
- If word changes do not make a sentence clear, write a different sentence.

## Exempt text

- Text inside fenced code blocks, including printed prompts and commands.
- Table cells. Write them as fragments, but obey the word rules.
- The frontmatter `description` field. It follows the trigger conventions in `skills/authoring-skills/references/descriptions.md`.
- Quoted examples that show good or bad output, for example in `skills/pr-review/references/comment-guidelines.md`.
- `references/retrospective.md`. It is a historical record.

## Existing text

- Every tracked markdown file obeys this rule, except the exempt text above.
- When you edit a paragraph, keep it at this standard. Do not add a sentence that breaks a rule.
- Files in `agents/` and `references/` are tuned prompts. A rewrite can change review behavior. Rewrite one file per change, keep the meaning, and run the skill once on a known PR after the change.
- The plan script copies marked blocks from `references/` into the shared context file. Keep the `<!-- block:name -->` markers and the tables in `references/profiles.md` intact.
