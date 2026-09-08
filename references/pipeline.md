# The review pipeline

Every review skill in this plugin runs the same six steps. A skill's SKILL.md holds only
what is different about it — this file is the shared part.

```
1 plan      run scripts/review-plan.sh — anchors, type, scale, budgets, pass list; writes the context skeleton
2 context   write the notes file — Settled facts and Open leads, nothing else
3 fan out   paste the plan's prompts, one agent each; delivery.md decides whether findings arrive
4 roll call delivery.md's roll call, then escalate anything that delivered nothing
5 triage    verify · dedup · tier · one-line suggested fix · label · freeze
6 deliver   the skill's own output: chat report, findings file, or PR comments
```

| Reference | Covers |
| --- | --- |
| [`profiles.md`](profiles.md) | The pass table, the type × scale matrix, the per-pass effort ceiling |
| [`severity.md`](severity.md) | A / B / C, the tie-breaker, type-aware tiering, the rendering table |
| [`delivery.md`](delivery.md) | Launch rules, the delivery clause, the roll call, the escalation ladder |

## 1 — Plan

`scripts/review-plan.sh --mode self|pr [--pr N] [--type T] [--scale S] [--deep N]
[--no-coverage] [--context-out <path>]` prints a `=== PLAN ===` block and **writes the
context skeleton** at the path its `context:` line names (see §2). Record the literal
`base` / `head` / `head0` SHAs — shell variables do not survive between tool calls, and
subagents never see them. The plan is authoritative for everything it prints.

Two things it hands back to you:

- `type: undetermined` — decide from the diff shape: a new export, public property, method
  or `.d.ts` addition → feature; edits inside existing logic plus a test → fix; the same
  behavior moved or renamed → refactor; only tests, docs or build files → chore. A parent
  PR or issue passed to the skill outranks the diff shape (`bug` → fix, `enhancement` →
  feature). Re-run the script with `--type` so the skeleton carries the resolved type.
- `type_conflict: <signal> → <type>` — a lower signal is more demanding than the declared
  type. **Never auto-upgrade.** Keep the declared type and hand the disagreement to the
  change pass as an explicit question.

`guard:` starting with `refuse:` ends the run — say the one-line reason and stop.

## 2 — Context file

The script wrote the skeleton. It already holds: the framing line, identity (branch, SHAs,
whether the head is checked out, type, scale, budgets, commits in order), the PR body, the
diff — inline when small, a whole numbered head file when a file is small and touched in
several places, patch paths otherwise — the diffstat and file lanes, the Settled facts the
script can prove (CI digest, image dimensions), the comments already on the PR (thread id,
author, bot or human, open or resolved, `path:line`, first line), the conventions excerpt —
chapters selected by the kinds of file touched and what the added lines use — the severity
rubric, the mode's rules, the read discipline and the scope rule.
**Do not re-quote, rewrite or re-derive any of it**, and do not read the conventions doc or
the diff yourself to check the skeleton — that is the spend the skeleton exists to remove.

You write **one file**, at the plan's `notes:` path, with the Write tool — never Edit the
skeleton. Edit needs a Read first, and that Read pulls the inline diff through your context,
the one cost the skeleton exists to remove. The skeleton's last section points every pass at
the notes file, so skip writing it when you have nothing to add. Three sections, in this order:

- **Settled facts** — facts you verified that a pass would otherwise derive: what a shared
  helper does, pre-change behavior, a consumer in another repo, a Flow connector's call.
  One line per claim with its evidence (`file:line`, a SHA, the command). Only what took you
  a call or two; the passes carry the budget for the rest.
- **Open leads** — suspicions you deliberately have not resolved. Every lead names exactly
  one owner pass (`[owner: change|code|tests]`); other passes do not investigate a lead
  they do not own, and triage inherits the owner's verdict.
- **Orchestrator notes** — only when the skeleton is wrong (a stale PR description, a
  mis-detected type). A notes file written **after** fan-out reaches only re-spawned agents:
  every pass reads once, at launch.

The rules, headers and framing the script copies into the skeleton live in
[`skeleton-blocks.md`](skeleton-blocks.md); the rubric it copies is severity.md's. They are
written for the passes — nothing in them is a step for you.

## 3 — Fan out

Launch the plan's `passes` in **one message**, sharing one barrier. The plan's
`=== PROMPTS ===` block is the prompt for each pass, verbatim — context and notes paths,
lane, resolved prompt adds, effort ceiling, delivery clause — with the `subagent_type` and
`model` its header names. Add nothing: questions, categories, output contracts and
verification rules live in the agent definitions (`agents/<name>.md`). Read
[`delivery.md`](delivery.md) before the first launch for the two launch rules the block
cannot enforce.

**Fallback**, only when the plugin's agents are unavailable: use `general-purpose` and paste
the body of the corresponding `agents/<name>.md` into the prompt.

Findings come back one per line:

```
<category> | <file>:<line> | <A|B|C> | <claim>[ | dup:<thread-id>]
```

`<line>` is the single declaration the claim is about — the selector, the statement, the
signature — not the block that contains it and not a range. Two passes that find the same
defect must land on the same line, or triage dedups by hand. `dup:` names the `## Already on
the PR` thread that makes the same claim on the same file; the line matters less than the
claim there, because a bot and a pass anchor differently.

After the finding lines, one line per Open lead the pass owns and closed without a finding:

```
lead cleared: <the lead, a few words> — <how, one clause>
```

A lead that comes back as neither a finding nor a `lead cleared:` line was not worked, and
triage treats it that way (§5.3).

Categories, by owning pass — `change`: `scope`, `behavior`, `fix`, `boundary`, `api`,
`impact`; `code`: `logic`, `conventions`, `reuse`, `maintainability`, `comments`; `tests`:
`tests`. The roll call goes by pass, the report by category. The change pass also returns its
deep **blocks** and a `BELOW LINE` list after the finding lines — the blocks are evidence, the
lines are what triage works on.

## 4 — Roll call

Run [`delivery.md`](delivery.md)'s roll call **before** triage: every pass by name with its
finding count, each marked `agent`, `self-run` or `missing`. A pass whose report was lost
looks exactly like a pass with nothing to say.

## 5 — Triage

1. **Verify** every finding against the code. What you cannot confirm is `accepted` with a
   one-line reason — kept in the report, never silently dropped.
2. **Dedup**: same file, line and claim from several agents is one finding; keep the
   clearest wording. Filed under different categories, it lives under the owning pass's
   category with a one-line pointer from the other. Two passes reaching the same defect is
   cross-checking, not waste — when they disagree on confidence, keep the verified wording.
   The declaration-line anchor (§3) is what lets this match on `file:line` instead of by hand.
   Then against `## Already on the PR`. A finding whose file and claim match an existing
   thread — `dup:` from a pass, or your own match — gets status `already raised (<author>,
   <id>)`. It stays in the frozen list with your verdict on the thread, `confirms` or
   `contradicts`, and is never posted as a new comment. An **open** thread that no pass
   reproduced is an `[orchestrator]` lead: verify it within the triage ceiling and record
   `confirmed by review` or `not reproduced`.
3. **Your own findings count.** What pre-verification turned up and no pass reported goes on
   the list tagged `[orchestrator]`, held to the same verification bar. So does an Open lead
   whose owner pass returned neither a finding nor a `lead cleared:` line — the lead was not
   worked, so it is yours now, never dropped.
4. **Judge, then tier.** One sentence of judgement per finding — does the evidence hold, what
   does it cost if merged as-is — then the final tier per [`severity.md`](severity.md),
   overriding the agent's proposal. Where an agent overstated, keep the corrected version and
   say so in one clause.
5. **Write the suggested fix as one line**, concrete to the file and line.
6. **Check every anchor against the diff.** A finding's `file` must be in the plan's
   `prod_files` / `test_files` / `binary_files`, and its line in a hunk. Re-anchor a coverage
   gap onto the diff line that motivates it, or mark it `summary-only`, so a skill offering to
   post never promises an inline comment the API will refuse.
7. **Label, then freeze the list.** Give every finding its Conventional Comments label per
   severity.md's rendering table. Triage ends with one canonical list — file, line, tier,
   category, label, status, claim, fix, `summary-only`, `dup` (the matched thread id, or
   empty) with its `confirms` / `contradicts` verdict, and how it was verified when not
   obvious. Chat summary, tier counts, report and PR comments all render from it.

Wording, because the report and any comment reuse these lines verbatim: every identifier in
backticks; one short sentence per claim with the single detail that makes it concrete; assume
the author knows the code; do not re-tell the trace that produced the finding.

## 6 — Deliver

The skill's own step. Nothing in this pipeline edits code, stages, or commits; the one
carve-out anywhere in the plugin is self-review's coverage stage, which restores every
mutant before the next. The files a run creates are the context skeleton, the patch files
when the diff is too large to inline, the orchestrator's notes file, and the skill's own
report.
