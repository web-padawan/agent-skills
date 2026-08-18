# Fix profile — premise check, five-agent cap

A bug fix runs a reduced pipeline: the premise pass before everything else, no scope, intent
or integration agents — **five agents in total**. The premise pass's investigative
procedure and precedence rules live in [`analysis.md`](analysis.md); this file holds the
decision rules, the launch order, and the cap.

## Launch order

1. Stage 0 as usual, then write the shared context file (analysis.md's **Shared context
   file** section) *before* the premise check, so that pass reads it like every other agent.
2. **Premise & history** (`agent-skills:premise-reviewer`), launched alone, with
   the delivery clause and `run_in_background: false` from arch-review's `delivery.md`
   like every other agent.
3. On `sound` or `unverified`: append its citations to the context file's **Settled facts**,
   then launch the rest of stage 1 as **one message of four agents**: the general, tests,
   root-cause and slop passes.
4. On `contradicted`: the run stops — see the next section.

## The premise decision

The premise pass answers one question: **does the project already have a decision about this
behavior?** A bug fix can be right in every detail and still be the wrong fix; reviewing the
implementation first is how a run spends its whole budget on code that should not exist.

- **No decision found** → record `premise: unverified` and continue.
- **Decision agrees with the fix** → record `premise: sound` with the citation, continue.
- **Decision contradicts the fix** → **stop the review.** Do not run the rest of stage 1
  or stages 2–4: their findings would describe code that the user's answer may delete.

On `contradicted`, report the citation in chat, then ask a single `AskUserQuestion`: how to
proceed, plus triage.md's Q1 (`Report`) options. **That question stands in for the stage-3
gate** — SKILL.md's "report only after the gate approves it" rule is satisfied by this
question, not bypassed. Write finalize.md's short report only when the user approved it;
otherwise the same content goes in the chat reply.

## Five agents, hard cap

A fix gets five agents in total:

- **premise & history** (first, alone) · **general** · **tests** · **root cause & blast
  radius** · **slop**.
- The scope, intent and integration passes fold into general
  (`agent-skills:general-reviewer`) — its definition carries the folded drive-by,
  intent-drift and conventions questions; the prompt must say the type is **fix** and name
  the repo's conventions doc.
- No deep review, and **`--deep` is ignored on a fix** — the five-agent cap wins; say so in
  one line when the flag was passed. Measured on a real fix branch, the old full profile ran
  16 agents and reported the same two A findings from two and three lenses each, in a
  1000-line report whose findings were 60% about code that the accepted fix does not
  contain. The lens machinery now lives entirely in `arch-review` — when a fix changes a
  contract or touches shared code, recommend `/agent-skills:arch-review <file:lines>` on the
  fix's hunks in the report instead of spending agents here.

If the fix looks too big for five agents, that is the finding — see the size check below.

## Size check — same stage as the premise check

Record the fix's production diff: `git diff --numstat <BASE>..HEAD -- <production globs>`.
A fix that adds new public API, a new cross-process message, or a new state machine is a
mislabeled feature or a re-architecture wearing a `fix:` prefix. Raise it as a `scope`
finding (B — a judgement call for the user) and weigh the premise question harder: an
approach that needs that much new code to fix a bug is often answering a question the
project already answered differently.
