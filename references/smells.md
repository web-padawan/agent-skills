# Smell vocabulary

The plan script copies the block below into the context file of a review when the repository
has no conventions doc and no owner rules (`scripts/sections/smells.sh`). Then a pass has a
shared name for a design problem. Edit the block here.

The smells come from Martin Fowler, _Refactoring_, second edition, chapter 3.

<!-- block:smells -->
> The repository has no conventions doc. Two rules bind this vocabulary:
>
> - A documented standard of the repository wins over a smell.
> - A smell is a judgement call, never a hard violation.

| Smell | Sign in the diff | Fix | Pass |
| --- | --- | --- | --- |
| Mysterious Name | A name that does not say what the code does | Rename | code |
| Duplicated Code | The same logic in two places of the diff or of the codebase | Extract one function | code |
| Feature Envy | A function that reads the data of another module more than its own | Move it to that module | code |
| Data Clumps | The same group of values passed together in several places | Make one object of them | code |
| Primitive Obsession | A string or a number that stands for a domain concept with rules | A small type for the concept | code |
| Repeated Switches | The same `switch` or `if` chain on one value in several places | Polymorphism or one lookup table | code |
| Shotgun Surgery | One change needs edits in many unrelated files | Move the parts that change together into one module | code |
| Divergent Change | One module changes for several unrelated reasons | Split the module by reason | code |
| Speculative Generality | A hook, a parameter or an abstraction with no current caller | Remove it until a caller needs it | change |
| Message Chains | `a.b().c().d()` to reach a value | Hide the chain behind one method | code |
| Middle Man | A class that only forwards calls to another | Call the target directly | code |
| Refused Bequest | A subclass that ignores or overrides most of what it inherits | Delegation instead of inheritance | code |
<!-- /block -->
