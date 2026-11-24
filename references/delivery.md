# Delivery — how agent findings reach the orchestrator

Every skill in this plugin that launches reviewer agents shares this file (`self-review`,
`pr-review`). A pass that never reports is worse than a pass that you skipped, because it
looks done.

## Launch rules

The `=== PROMPTS ===` block of the plan is the prompt of each pass. Paste it verbatim, with
the `subagent_type` and `model` that its header names. Make one Agent call per pass, all in
one message.

**Omit `name`.** A named agent ends its turn idle and still alive, and its final text never
returns to you.

A launch can be asynchronous. Then each report arrives as a task notification, and the
harness starts your turn again. Wait for that turn, and do not poll a listing tool. For each
such turn, write at most one line, for example `Done: code, tests. Waiting on: change.`

Every printed prompt ends with this clause. The script copies the clause from here by
marker. Edit the clause here only:

<!-- block:delivery-clause -->
```
Your findings are the deliverable. Return them as the CONTENT of your final message.
If you have a SendMessage tool, ALSO send them to `main` in the same format.
Do not write them to a file, and do not end your turn without them.
```
<!-- /block -->

## Waiting

Spend the wait only on leads that the passes cannot reach:

- a consumer in another repository (a wrapper, a downstream app)
- a parent issue
- a release note
- a browser check

Leave every file that the passes read to the passes. Notes that you write after fan-out
reach no pass that already runs. Log what you verified, so that the report can distinguish a
confirmed claim from an accepted one.

## Roll call — run before triage

Print one line per pass that you launched, with its marker and its finding count:

```
Delivery roll call
  change              ✅ agent · 5 findings + 2 blocks
  code                ✅ agent · 8 findings
  tests               ✅ agent · 8 findings
```

Markers:

- `✅ agent`: you hold the findings of the pass
- `⚠️ self-run`: you answered the questions of the pass yourself
- `❌ missing`: nobody covered the pass

Carry the marker of each pass into the report.

## Fallback — a pass that delivered nothing

A completion that carries no finding line and no `NO FINDINGS` is a lost report.

1. Launch the pass again once from the same `=== PROMPTS ===` block, with no `name`.
2. If that launch also delivers nothing, read the files and answer the questions of
   `agents/<name>.md` yourself. Tag each finding of that pass `self-run`.

Treat a self-run pass as weaker evidence than an agent pass. You review with the context
that you already hold. That context makes you less likely to notice the assumptions of the
diff. When you present findings, say which passes were self-run.
