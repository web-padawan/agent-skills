# Delivery — how agent findings reach the orchestrator

Every skill in this plugin that launches reviewer agents shares this file (`self-review`,
`pr-review`). A pass that never reports is worse than a pass that you skipped, because it
looks done. A few launch choices decide whether findings arrive at all, and the defaults
lose them. How you spend the wait decides whether the findings that you get are worth a
report.

## Launch rules

The `=== PROMPTS ===` block of the plan is the prompt of each pass. Paste it verbatim, with
the `subagent_type` and `model` that its header names. Make one Agent call per pass, all in
one message. The block cannot do two things for you:

- **Omit `name`.** A named agent becomes an addressable teammate. It ends its turn idle and
  still alive, and its final text never returns to you. Name an agent only when you must
  message it mid-run.
- **Where the Agent tool has `run_in_background`, pass `false`.** Triage is a barrier, so a
  synchronous run is what you want. Without the parameter, every launch is asynchronous and
  reports arrive as task notifications. Treat such a notification as a normal launch.

Every printed prompt ends with this clause, so that a second channel exists. The script
copies the clause from here by marker. Edit the clause here only:

<!-- block:delivery-clause -->
```
Your findings are the deliverable. Return them as the CONTENT of your final message.
If you have a SendMessage tool, ALSO send them to `main` in the same format.
Do not write them to a file, and do not end your turn without them.
```
<!-- /block -->

**Recognize a lost report.** A message like
`{"type":"idle_notification","idleReason":"available"}`, or a completion that carries no
findings, is a **delivery failure**. Mark the pass `❌ missing` and escalate it.

**Recognize a truncated report.** A result that ends in
`[result truncated — ask the agent for the rest via SendMessage]`, or in a half-finished
sentence, is a **partial delivery**. Partial delivery is the normal outcome when you name an
agent. It silently drops whatever the pass ranked last, often its deep blocks or its
`checked and cleared` notes.

`SendMessage` the agent once for the remainder before you triage. If the agent is gone,
self-run only the missing section and tag those findings `self-run`. Mark the pass
`⚠️ truncated` in the roll call until you hold the remainder.

## Waiting — verify what the passes cannot reach

When launches are asynchronous, the harness re-invokes you as each agent completes. The
harness forces that turn, so wait for it rather than poll a listing tool. For the forced
turns, emit at most one line, in the vocabulary of the roll call:
`Done: code, tests. Waiting on: change.`

Spend the wait only on leads that the passes cannot reach:

- a consumer in another repository (a Flow connector, a downstream app)
- a parent issue
- a release note
- a browser check

Leave every file that the passes read to the passes. Anything that you verify now duplicates
a pass that verifies it at the same moment. Notes that you append to the context file after
fan-out reach only re-spawned agents. Log what you verified, so that the report can
distinguish a confirmed claim from an accepted one.

If no lead lies outside the reach of the passes, end the turn quietly and wait for the
notification.

## Roll call — run before triage

List every agent that you launched and tick the ones whose findings you hold. Print the roll
call by pass name, one per line, with the finding count. A line like
`11 ✅ · 5 ✅ · boundary ✅` mixes two identifier systems and tells the reader nothing about
what the pass checked.

```
Delivery roll call
  change              ✅ agent · 5 findings + 2 blocks
  code                ✅ agent · 8 findings
  tests               ✅ agent · 8 findings
```

Markers:

- `✅ agent`
- `⚠️ truncated`
- `⚠️ self-run`
- `❌ missing`
- `⏳ running`

The finding count also makes the roll call a yield tally. The tally tells you later whether a
pass earns its place.

## Escalation — for each pass that delivered nothing

Escalate the **mechanism**. A retry down the same channel fails identically:

0. **Truncated, not missing?** `SendMessage` that agent once for the remainder. The agent is
   alive and the channel worked, so only the result is incomplete.
1. **Re-spawn once** from the same `=== PROMPTS ===` block, with no `name`.
2. **Self-run the pass**: read the files and answer the questions of that pass yourself. The
   questions are in the `agents/<name>.md` definition of the pass. Tag every finding that the
   self-run yields `self-run`.

If you named an agent against the launch rule, ping it once before you re-spawn. Restate the
output contract and what you have already verified.

Carry the status of each pass, `agent`, `self-run`, or `missing`, into the report.

Treat a self-run pass as **weaker evidence** than an agent pass. You review with the same
context that produced the diff. That context makes you the reader least likely to notice the
assumptions of the diff. When you present findings, say which passes were self-run.
