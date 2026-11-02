# Encode lessons in structure

This rule applies when you fix a recurring failure of a skill, an agent or a script in this
repository.

A text instruction works only when the agent reads it, remembers it and obeys it. A mechanism
enforces the rule without that cooperation. Each correction, failed run and unexpected result
is a signal.

## When the rule applies

- You write the same instruction a second time.
- The user corrects the same kind of output a second time.
- A review run misses a finding, or posts a wrong one, for a reason that can recur.

## Pick the strongest mechanism

Use the first mechanism in this list that can hold the fix:

1. **A state that cannot occur.** The script never prints the wrong value. Example:
   `review-plan.sh` prints literal SHAs, so no pass resolves them.
2. **A refusal.** A script exits with an error on bad input. Example: `post-comment.sh`
   refuses a message that does not start with a bold label.
3. **A contract field.** A plan line or an agent output format carries the fact. Example:
   the `dup:<id>` field on a finding line.
4. **A smoke check.** `scripts/smoke.sh` fails when the behavior breaks.
5. **Text.** A checklist item, a gotcha or a rule. Use text only when the fix needs judgment.

Agents copy what the surrounding files already do. A weak guard becomes the template for the
next change.

## When the fix is text

- Put the rule in the file that the agent reads at the decision point.
- Add one concrete example of the failure.
- Make the rule checkable. Name the input, the wrong output and the correct output.

If the fix is structural, delete the text that it replaces. The instruction is the symptom.

## Route each lesson

| Lesson | Layer |
| --- | --- |
| A one-off | A memory note, or nothing |
| A recurring fix in one skill or agent | A script check, a contract field, or a checklist item in that file |
| A recurring fix across skills | The plan script, a shared reference, or a rule in `.claude/rules/` |

Finish each lesson in the same session. Apply the fix now, or record a task that names the
file and the change.

## Anti-patterns

- You acknowledge a correction and record nothing. "I will remember" does not persist.
- You record a lesson and route it to no layer. A note about a missing check does not
  create the check.
- You fix one instance and leave the recurring pattern in place.
