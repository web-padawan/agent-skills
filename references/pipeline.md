# The review pipeline

Every review skill in this plugin runs the same six steps. The SKILL.md of a skill holds only
what is different about that skill. This file is the shared part.

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
[--no-coverage] [--context-out <path>]` prints a `=== PLAN ===` block. The script also
**writes the context skeleton** at the path that its `context:` line names (see §2). Record
the literal `base` / `head` / `head0` SHAs. Shell variables do not survive between tool
calls, and subagents never see them. The plan is authoritative for everything that it prints.

The plan leaves two decisions to you:

- `type: undetermined`. Decide the type from the diff shape:
  - a new export, public property, method or `.d.ts` addition: feature
  - edits inside existing logic plus a test: fix
  - the same behavior moved or renamed: refactor
  - only tests, docs or build files: chore

  A parent PR or issue passed to the skill outranks the diff shape (`bug` means fix,
  `enhancement` means feature). Re-run the script with `--type` so that the skeleton carries
  the resolved type.
- `type_conflict: <signal> → <type>`. A lower signal is more demanding than the declared
  type. **Never auto-upgrade.** Keep the declared type. Hand the disagreement to the change
  pass as an explicit question.

A `guard:` value that starts with `refuse:` ends the run. Say the one-line reason and stop.

## 2 — Context file

The script wrote the skeleton. The skeleton already holds these parts:

- the framing line
- the identity: branch, SHAs, whether the head is checked out, type, scale, budgets, commits
  in order
- the PR body
- the diff, in one of three forms:
  - inline, when the diff is small
  - a whole numbered head file, when a file is small and touched in several places
  - patch paths otherwise
- the diffstat and the file lanes
- the Settled facts that the script can prove (CI digest, image dimensions)
- the comments already on the PR: thread id, author, bot or human, open or resolved,
  `path:line`, first line
- the conventions excerpt: chapters selected by the kinds of file touched and by what the
  added lines use
- the severity rubric
- the rules of the mode
- the read discipline
- the scope rule

**Do not re-quote, rewrite or re-derive any part of the skeleton.** Do not read the
conventions doc or the diff yourself to check the skeleton. That spend is what the skeleton
exists to remove.

You write **one file**, at the `notes:` path of the plan, with the Write tool. Never Edit the
skeleton. Edit needs a Read first, and that Read pulls the inline diff through your context.
That pull is the one cost that the skeleton exists to remove.

The last section of the skeleton points every pass at the notes file. When you have nothing
to add, do not write the notes file. The notes file has three sections, in this order:

- **Settled facts**: facts that you verified and that a pass would otherwise derive. For
  example, what a shared helper does, pre-change behavior, a consumer in another repo, the
  call of a Flow connector. Write one line per claim with its evidence (`file:line`, a SHA,
  the command). Record only what took you a call or two. The passes carry the budget for the
  rest.
- **Open leads**: suspicions that you deliberately have not resolved. Every lead names exactly
  one owner pass (`[owner: change|code|tests]`). Other passes do not investigate a lead that
  they do not own. Triage inherits the verdict of the owner pass.
- **Orchestrator notes**: only when the skeleton is wrong (a stale PR description, a
  mis-detected type). A notes file written **after** fan-out reaches only re-spawned agents.
  Every pass reads once, at launch.

The rules, headers and framing that the script copies into the skeleton live in
[`skeleton-blocks.md`](skeleton-blocks.md). The rubric that the script copies is the one in
severity.md. Those blocks address the passes, and nothing in them is a step for you.

## 3 — Fan out

Launch the `passes` of the plan in **one message**, so that they share one barrier. The
`=== PROMPTS ===` block of the plan is the prompt for each pass, verbatim. The block holds:

- the context and notes paths
- the lane
- the resolved prompt adds
- the effort ceiling
- the delivery clause

Launch each pass with the `subagent_type` and `model` that its header names.

Add nothing to the prompt. Questions, categories, output contracts and verification rules
live in the agent definitions (`agents/<name>.md`). Read [`delivery.md`](delivery.md) before
the first launch. It holds the two launch rules that the block cannot enforce.

**Fallback**, only when the plugin agents are unavailable: use `general-purpose` and paste
the body of the corresponding `agents/<name>.md` into the prompt.

Findings arrive one per line:

```
<category> | <file>:<line> | <A|B|C> | <claim>[ | dup:<thread-id>]
```

`<line>` is the single declaration that the claim is about: the selector, the statement, the
signature. It is not the block that contains the declaration, and not a range. Two passes
that find the same defect must land on the same line. Otherwise triage dedups by hand.
`dup:` names the `## Already on the PR` thread that makes the same claim on the same file.
For that match the line matters less than the claim, because a bot and a pass anchor
differently.

After the finding lines, the pass writes one line per Open lead that it owns and closed
without a finding:

```
lead cleared: <the lead, a few words> — <how, one clause>
```

A lead that returns as neither a finding nor a `lead cleared:` line was not worked. Triage
treats such a lead that way (§5.3).

Categories, by owner pass:

- `change`: `scope`, `behavior`, `fix`, `boundary`, `api`, `impact`
- `code`: `logic`, `conventions`, `reuse`, `maintainability`, `comments`
- `tests`: `tests`

The roll call goes by pass, the report by category. The change pass also returns its deep
**blocks** and a `BELOW LINE` list after the finding lines. The blocks are evidence. The
lines are what triage works on.

## 4 — Roll call

Run the roll call of [`delivery.md`](delivery.md) **before** triage. List every pass by name
with its finding count, each marked `agent`, `self-run` or `missing`. A pass with a lost
report looks exactly like a pass with nothing to say.

## 5 — Triage

1. **Verify** every finding against the code. Mark what you cannot confirm as `accepted`,
   with a one-line reason. Keep such a finding in the report. Never drop it silently.
2. **Dedup**: the same file, line and claim from several agents is one finding. Keep the
   clearest wording. When agents filed the finding under different categories, it lives
   under the category of the owner pass, with a one-line pointer from the other. Two passes
   that reach the same defect is cross-checking, not waste. When they disagree on
   confidence, keep the verified wording. The declaration-line anchor (§3) is what lets this
   match on `file:line` instead of by hand.

   Then dedup against `## Already on the PR`. A finding whose file and claim match an
   existing thread gets status `already raised (<author>, <id>)`. The match comes from
   `dup:` on a pass finding or from your own comparison. The finding stays in the frozen
   list with your verdict on the thread, `confirms` or `contradicts`. Never post it as a new
   comment.

   An **open** thread that no pass reproduced is an `[orchestrator]` lead. Verify it within
   the triage ceiling and record `confirmed by review` or `not reproduced`.
3. **Your own findings count.** A finding from your pre-verification that no pass reported
   goes on the list, tagged `[orchestrator]`. An Open lead whose owner pass returned neither
   a finding nor a `lead cleared:` line also goes on the list. Nobody worked that lead, so it
   is yours now. Never drop it. Hold every `[orchestrator]` finding to the same verification
   bar.
4. **Judge, then tier.** Write one sentence of judgment per finding: does the evidence hold,
   and what does it cost if merged as-is. Then set the final tier per
   [`severity.md`](severity.md), and override the proposal of the agent. Where an agent
   overstated, keep the corrected version and say so in one clause.
5. **Write the suggested fix as one line**, concrete to the file and line.
6. **Check every anchor against the diff.** The `file` of a finding must appear in the
   `prod_files`, `test_files` or `binary_files` list of the plan. Its line must be in a
   hunk. Re-anchor a coverage gap onto the diff line that motivates it, or mark it
   `summary-only`. Then a skill that offers to post never promises an inline comment that
   the API will refuse.
7. **Label, then freeze the list.** Give every finding its Conventional Comments label per
   the rendering table of severity.md. Triage ends with one canonical list. Each entry
   holds:
   - file
   - line
   - tier
   - category
   - label
   - status
   - claim
   - fix
   - `summary-only`
   - `dup`: the matched thread id, or empty, with its `confirms` / `contradicts` verdict
   - how you verified the finding, when that is not obvious

   Chat summary, tier counts, report and PR comments all render from this list.

Wording rules, because the report and any comment reuse these lines verbatim:

- put every identifier in backticks
- write one short sentence per claim, with the single detail that makes it concrete
- assume that the author knows the code
- do not re-tell the trace that produced the finding

## 6 — Deliver

The skill owns this step. Nothing in this pipeline edits code, stages, or commits. The one
carve-out anywhere in the plugin is the coverage stage of self-review, which restores every
mutant before the next. A run creates these files:

- the context skeleton
- the patch files, when the diff is too large to inline
- the notes file of the orchestrator
- the report of the skill
