# The review pipeline

Every review skill in this plugin runs the same six steps. A skill's SKILL.md holds only
what is different about it — this file is the shared part, and it is the only place these
rules are written down.

```
1 plan      run scripts/review-plan.sh — anchors, type, scale, pass list, budgets, paths
2 context   write the shared context file the plan names
3 fan out   launch the plan's pass list; delivery.md decides whether findings arrive
4 roll call delivery.md's roll call, then escalate anything that delivered nothing
5 triage    verify · dedup · tier · one-line suggested fix
6 deliver   the skill's own output: chat report, findings file, or PR comments
```

| Reference | Covers |
| --- | --- |
| [`profiles.md`](profiles.md) | The pass table and the type × scale matrix — the plan script parses it |
| [`severity.md`](severity.md) | A / B / C, the tie-breaker, type-aware tiering |
| [`delivery.md`](delivery.md) | Launch rules, the delivery clause, the roll call, the escalation ladder |
| [`rationale.md`](rationale.md) | Why the pipeline is shaped this way — measured, not guessed |

## 1 — Plan

`scripts/review-plan.sh --mode self|pr|arch [--pr N] [--type T] [--scale S] [--deep N]
[--no-coverage]` wraps `get-pr-context.sh` and prints a `=== PLAN ===` block: the guard
verdict, the literal `base` / `head` / `head0` SHAs, the change type with its signal, the
scale tier with its counts, the pass list with each pass's agent, stage, model and folds,
the mutant budget, the conventions doc, and the report paths. Record the SHAs as literals —
shell variables do not survive between tool calls, and subagents never see them.

The plan is authoritative for everything it prints. Two things it hands back to you:

- `type: undetermined` — decide from the diff shape: a new export, public property, method
  or `.d.ts` addition → feature; edits inside existing logic plus a test → fix; the same
  behavior moved or renamed → refactor; only tests, docs or build files → chore. A parent
  PR or issue passed to the skill outranks the diff shape (`bug` → fix, `enhancement` →
  feature).
- `type_conflict: <signal> → <type>` — a lower signal is more demanding than the declared
  type. **Never auto-upgrade.** Keep the declared type and hand the disagreement to the
  scope pass as an explicit question: reviewing against the author's claim is what tests
  it, and the more demanding profile would examine a different risk instead of the mislabel.

`guard:` starting with `refuse:` ends the run — say the one-line reason and stop.

## 2 — Context file

Write it once, at the path the plan names, before launching anything (on a fix, before the
premise pass too). Every agent prompt then carries its **path** instead of a retyped
paragraph: prompts drift apart when the context is inline, and a correction reaches only
the agents launched after you found it.

It holds: branch, the literal `base` and `head` SHAs with the note that the diff under
review is `git diff <base>..<head>`, `git diff --stat`, the changed-file list, the type and
its signal, the scale tier with counts and any override, PR title/body when a PR exists, a
summary of the parent PR/issue when one was given, the one-line intent and where it came
from, [`severity.md`](severity.md)'s rubric and its two verbatim rules, plus the three
sections below.

When you discover something the context gets wrong, append it under `## Orchestrator notes`
(e.g. "the PR description is stale: it documents X, the code does Y") so every later agent
reads the correction once, identically.

**Conventions docs** — name the repo's sources in priority order, with paths: the plan's
`conventions_doc`, the guideline chapters covering what this diff touches, and any
topic-specific rules doc that governs the change. Agents that have to find these themselves
spend tool calls doing it, and each one finds a different subset.

**Settled facts** — what you verified in the plan step, plus the premise pass's citations on
a fix. One line per claim with its evidence (`file:line`, a SHA, an issue number, or the
command that produced it). Head the section with this instruction, verbatim:

> Each entry is authoritative. Do not open the file it came from. If a finding of yours
> depends on an entry being wrong, report that as a finding with your reasoning — one line,
> no re-investigation.

**Open leads** — suspicions you deliberately have not resolved. Every lead names exactly
one owner pass:

```
- [owner: tests] The append branch is never exercised with an already-added component.
- [owner: root cause] `removeAll()` may still bypass the guard the fix restored.
```

Other passes do not investigate a lead they do not own; triage inherits the owner's verdict.

**On a PR scope**, add this rule block verbatim — the head may not be checked out:

> Lines prefixed `+` in the diff are code the author HAS ALREADY WRITTEN — review their
> quality, never suggest implementing them. Only flag issues introduced by this change, not
> pre-existing code. Read post-change file content with `git show <head>:<path>` (literal
> SHA), never from the working tree, unless the context file says the checked-out branch is
> the head.

## 3 — Fan out

Launch the plan's `passes` list. `stage: pre` runs **alone and first**; everything marked
`stage: batch` goes out in **one message**, sharing one barrier. Each prompt is exactly:
the context file path, the pass's `folds` and `prompt adds` from the plan, and
[`delivery.md`](delivery.md)'s delivery clause verbatim. Questions, categories, output
contracts and verification rules live in the agent definitions (`agents/<name>.md`) — never
paste them into a prompt.

Read [`delivery.md`](delivery.md) before the first launch and follow it exactly: it is what
decides whether findings arrive at all. Its waiting rule applies here — pre-verify the
claims you expect while a batch is in flight, never poll.

**Fallback**, only when the plugin's agents are unavailable: use `general-purpose` and paste
the body of the corresponding `agents/<name>.md` into the prompt.

Findings come back one per line:

```
<category> | <file>:<line> | <A|B|C> | <claim>
```

Categories: `general`, `scope`, `intent`, `requirements`, `premise`, `root-cause`,
`behavior`, `integration`, `tests`, `slop`, `cleanup` — plus `architecture`, `boundary`,
`impact` and `api` when arch-review's lenses ran.

### The premise gate — fix only

The premise pass answers one question: **does the project already have a decision about
this behavior?** A bug fix can be right in every detail and still be the wrong fix.

- **No decision found** → `premise: unverified`, continue.
- **Decision agrees with the fix** → `premise: sound` with the citation, continue. Append
  its citations to the context file's **Settled facts** before launching the batch, or every
  later pass re-derives them.
- **Decision contradicts the fix** → **stop.** Do not launch the batch, do not triage:
  the findings would describe code the user's answer may delete. Report the citation and ask
  the user with a single `AskUserQuestion` — that question stands in for the skill's own
  gate. `pr-review` is the exception: a contradicted premise there is the top A finding, not
  a stop.

Also record the fix's production diff (`git diff --numstat <base>..<head> -- <source
globs>`). A fix that adds new public API, a new cross-process message, or a new state
machine is a mislabeled feature — raise it as a `scope` finding (B, a judgement call for
the user) and weigh the premise question harder.

## 4 — Roll call

Run [`delivery.md`](delivery.md)'s roll call **before** triage: every pass by name with its
finding count, each marked `agent`, `self-run` or `missing`. Triaging first means silently
triaging a subset — a pass whose report was lost looks exactly like a pass with nothing to
say. A pass that reported nothing has *not* come back clean.

## 5 — Triage

1. **Verify** every finding against the code. Agents produce false positives. What you
   cannot confirm is `accepted` with a one-line reason — kept in the report, never silently
   dropped.
2. **Dedup**: same file, line and claim from several agents is one finding; keep the
   clearest wording, note which categories raised it. Lenses converging on one change is
   signal — merge and mark `[3-lens]` / `[2-lens]`.
3. **Assign the final tier** per [`severity.md`](severity.md), overriding the agent's
   proposal. Where an agent overstated a claim, keep the corrected version and say so in one
   clause.
4. **Write the suggested fix as one line.** Concrete and specific to the file and line: "move
   the listener removal into `disconnectedCallback`", never "consider refactoring this".

Wording, because the report and any comment reuse these lines verbatim: every identifier,
method, type and compared literal in backticks; plain developer words, no invented labels;
one short sentence per claim, keeping the single detail that makes it concrete.

## 6 — Deliver

The skill's own step. Nothing in this pipeline edits code, stages, or commits; the one
carve-out anywhere in the plugin is self-review's coverage stage, which restores every
mutant before the next.
