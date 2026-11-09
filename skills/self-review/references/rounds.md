# Stage: rounds

A **round** is one fan-out of the passes. One round does not find everything in a large
feature. On four feature branches of vaadin/web-components, a second round on the same head
found 61 new findings after 92 in the first, 19 of them B.

The plan lists the stage in its `stages:` block, with the line of `scripts/stages/rounds.sh`
under it:

```
stages:
  rounds: slot after-triage, budget 2, ask no, ref skills/self-review/references/rounds.md
    round: 1 of 2
```

- **Budget**: the plan sets it from the change type and the scale tier. The user flag
  `--rounds N` sets it to N. Pass it to the plan as `--budget rounds=N`.
- **Count**: a findings file of the same head without `verdict` is a run that did not
  finish, so the next plan prints its round plus 1. A findings file with `verdict` is a
  finished run, so a new run starts at round 1.

## After triage

Read the `round: <k> of <n>` line of the plan:

- When k is less than n and this round added a confirmed A or B finding, write the findings
  file per finalize.md, without `verdict`. Re-run the plan with the same flags. Then repeat
  steps 3 to 5 of the skill with its new prompts.
- Otherwise, continue to the gate.

The re-run plan lists the findings of the earlier rounds in the skeleton, so that the passes
look for what those rounds missed. Keep the notes file. The frozen list grows by the new
findings of each round.
