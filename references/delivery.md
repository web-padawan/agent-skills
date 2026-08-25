# Delivery — how agent findings reach the orchestrator

Shared by every skill in this plugin that launches reviewer agents (`arch-review`, `self-review`, `pr-review`). A pass that never reports is worse than a pass you skipped: it looks done. A few launch choices decide whether findings arrive at all, and the **defaults lose them** — and how you spend the wait decides whether the findings you get are worth reporting.

## Launch rules — all three mandatory

- **Pass `run_in_background: false` on every agent, if your Agent tool has that parameter.** Triage is a barrier — you need all findings before verifying anything — so a synchronous run is what you actually want, and it makes each agent's report arrive as its tool result. Where the tool exposes no such parameter, every launch is asynchronous and reports arrive as task notifications instead: that is the harness working normally, **not** a delivery failure, and not a reason to relaunch. Check the tool's schema rather than assuming either shape.
- **Do not pass `name`.** A named agent becomes an addressable teammate: it ends its turn *idle and still alive*, and its final text is never returned to you. Name an agent only when you genuinely need to message it mid-run.
- **This clause verbatim in every prompt**, so a second channel exists:

```
Your findings are the deliverable. Return them as the CONTENT of your final message.
If you have a SendMessage tool, ALSO send them to `main` in the same format.
Do not write them to a file, and do not end your turn without them.
```

**Recognize a lost report.** A message like `{"type":"idle_notification","idleReason":"available"}`, or a completion carrying no findings, is a **delivery failure** — not a clean pass. Never record it as `NO FINDINGS`.

## Waiting — pre-verify, do not poll

When launches are asynchronous you will be re-invoked as each agent completes. Do not poll a listing tool in a loop, and do not emit "still waiting" turns — they cost a round trip and tell the reader nothing.

Spend the wait on verification instead. The claims a reviewer agent is about to make are checkable before they arrive: does that API actually exist (disassemble the jar, grep the package), does the cited test actually cover that path, do the sibling files really set the precedent the agent will invoke, is the change's own description accurate about what shipped. This is triage work either way, so doing it early costs nothing — and it is what lets you report a finding as *corrected* rather than forwarding an overstatement. Log what you verified so the report can distinguish a confirmed claim from an accepted one.

If a batch genuinely has nothing left to pre-verify, end the turn quietly and wait for the notification.

## Roll call — run before triage

List every agent you launched and tick the ones whose findings you actually hold. **Print it by pass name, one per line, with the finding count.** Never by number: a line like `11 ✅ · 5 ✅ · boundary ✅` mixes two identifier systems and tells the reader nothing about what was checked.

```
Delivery roll call
  code                ✅ agent · 8 findings
  tests               ✅ agent · 8 findings
  boundary lens       ✅ agent · 3 findings + narrative block
```

Markers: `✅ agent` · `⚠️ self-run` · `❌ missing` · `⏳ running`. The finding count makes the roll call double as a yield tally, which is what tells you later whether a pass earns its place. Use the same names in any mid-run status line — `Done: code, tests. Waiting on: boundary lens.` — so the reader never has to map a digit to a purpose.

## Escalation — for each pass that delivered nothing

Escalate the **mechanism** — a retry down the same channel fails identically, so never just re-send the same call:

1. **Ping once**, only if the agent is named and still alive: restate the output contract, name the 2–3 questions you most need answered, and include the facts you have already verified so it does not spend its run re-deriving them.
2. **Re-spawn once** with no `name` (and `run_in_background: false` where the tool has it) — a different channel, not a second try down the broken one.
3. **Self-run the pass**: read the files and answer that pass's questions yourself (the questions are in the pass's `agents/<name>.md` definition). Tag every finding it yields `self-run`.

Never drop a pass silently, and never let a lost report pass for a clean one. Carry each pass's status — `agent`, `self-run`, or `missing` — into the report.

Treat a self-run pass as **weaker evidence** than an agent pass: you are reviewing with the same context that produced the diff, which makes you the reader least likely to notice what it takes for granted. Say which passes were self-run when presenting findings, rather than presenting them as independent confirmation.
