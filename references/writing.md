# Writing standard

This file holds the writing rules of this plugin. The rules adapt ASD-STE100 Issue 9, the
standard for Simplified Technical English. No STE dictionary is enforced.

A skill that writes text for a person reads this file before it writes. The rule in
`.claude/rules/writing-style.md` applies this file to the markdown of this repository.
`scripts/prose-check.sh` finds the patterns of [`banned-patterns.md`](banned-patterns.md).
The rules below need judgment.

<!-- block:ste -->
## Words

- Use familiar words. Explain an unfamiliar word where you first use it.
- Use one name for each concept in all files. Do not use a synonym for variety.
- Select the shortest name that identifies the object without ambiguity.
- Do not use slang, regional terms, or jargon as technical names.
- Use technical nouns as nouns and technical verbs as verbs.
- Use American English spelling.
- Use no more than three words in a noun group. Write a longer official name in full first, then use a short form.
- Use English words instead of Latin abbreviations. Write `for example`, not `e.g.`
- Use gender-neutral names for roles.
- Do not use a word that adds emphasis but no fact. Examples: `robust`, `powerful`, `crucial`, `seamless`, `truly`.
- Do not use an analogy or a metaphor. Describe the object in literal terms.
- Do not write `not just X, but Y`. State what the object is.
- Do not invent a hyphenated adjective. Use a compound that a dictionary lists.

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
- Delete a clause that gives no fact. Example: `before we call the work done`.
- Do not use a colon to join two clauses. Use a colon before a list or a label.

## Punctuation

- Do not use semicolons in prose.
- Do not use em-dashes or en-dashes in prose. Write two sentences, or use a comma. A heading may use a dash.
- Use parentheses only for a reference, an identifier, an abbreviation, an explanation of a word, or an alternative.
- Use hyphens to show which words form one unit, for example `read-only`.
- Use straight quotes. Do not use curly quotes.
- Do not use a middle dot (`·`) as a separator in prose. Use a comma.

## Headings and emphasis

- Use sentence case in a heading. The H1 of a `SKILL.md` keeps the skill name in title case.
- Write a heading that describes the content. Do not write a clever label.
- Use bold for a label or for a defined term. Do not use bold for decoration.

## Paragraphs and structure

- Give one topic in each paragraph. Use no more than six sentences in a paragraph.
- Use a vertical list for a set with more than two items or with conditions.
- Use connecting words to show how sentences relate. Use the same words for the same relation.
- Put an instruction in the main text. Use a note only to give information.
- If word changes do not make a sentence clear, write a different sentence.
<!-- /block -->

<!-- block:tone -->
## Tone

- Put the claim, the problem or the goal in the first sentence.
- State a verified fact as a fact. Do not add a hedge to it.
- Name each part that you did not verify. Write `Not verified on a device yet`, not
  `this could potentially fail`.
- Describe the code, not the author. Write `The check misses null`, not `You forgot null`.
- Say why the problem matters. Name the scenario and the environment where it occurs.
- Copy an error message exactly, in a code block. Do not paraphrase it.
- Link a related issue or document. Do not copy its content.
- Put each code element in backticks, for example a method, a property or a file name.
  A backtick also prevents an accidental user mention.
- Leave no trace of how you found a fact. Do not write `While I worked on X, I saw Y`.
- Do not write a greeting, thanks, praise, an apology, a preamble or a closing summary.
- Do not use an emoji or an exclamation mark.
<!-- /block -->

<!-- block:tells -->
## Patterns of generated text

Readers use these patterns to identify generated text. The script cannot find all of them.

- Do not open with broad context. Start with the specific fact.
- Do not end with a sentence that repeats the text. End with the next step, or stop.
- Do not announce the count of a list. Write the list.
- Do not write a set of adjectives that adds no fact, for example `fast, reliable and simple`.
- Write a heading as a statement, not as a question.
- Use one note at most in a document.
<!-- /block -->
