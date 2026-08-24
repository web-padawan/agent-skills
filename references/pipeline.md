# The review pipeline

Every review skill in this plugin runs the same six steps. A skill's SKILL.md holds only
what is different about it — this file is the shared part, and it is the only place these
rules are written down.

```
1 plan      run scripts/review-plan.sh — anchors, type, scale, pass list, budgets, paths
2 context   write the shared context file and the two prepared patches it names
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
scale tier with its counts, the pass list with each pass's agent, stage, model, read lane
and folds, the mutant budget, the conventions doc, the changed files split into
`prod_files` / `test_files` / `comment_files`, and the context, patch and report paths. Record the SHAs as literals —
shell variables do not survive between tool calls, and subagents never see them.

The plan is authoritative for everything it prints. Two things it hands back to you:

- `type: undetermined` — decide from the diff shape: a new export, public property, method
  or `.d.ts` addition → feature; edits inside existing logic plus a test → fix; the same
  behavior moved or renamed → refactor; only tests, docs or build files → chore. A parent
  PR or issue passed to the skill outranks the diff shape (`bug` → fix, `enhancement` →
  feature).
- `type_conflict: <signal> → <type>` — a lower signal is more demanding than the declared
  type. **Never auto-upgrade.** Keep the declared type and hand the disagreement to the
  fit pass as an explicit question: reviewing against the author's claim is what tests
  it, and the more demanding profile would examine a different risk instead of the mislabel.

`guard:` starting with `refuse:` ends the run — say the one-line reason and stop.

## 2 — Context file and prepared patches

### The patches

Before the context file, write the two patches the plan names — `patch_prod:` and
`patch_tests:` — from the plan's literal SHAs and its `prod_files:` / `test_files:` lists:

```
git diff -U10 <base>..<head> -- <prod_files>  > <patch_prod>
git diff -U5  <base>..<head> -- <test_files>  > <patch_tests>
```

Two reasons for the wide context. Agents that cannot see enough around a hunk fall back to
`git show <head>:<path>` and read a whole file to answer a question about thirty lines, and
an agent reading the diff alone misses moved code. Ten lines each side is cheaper than
either. **If the prod patch comes out over ~1500 lines, regenerate it at `-U3`** and let
agents open the few files they must — at that size the extra context costs more than it
saves. An empty `test_files:` means no test patch; say so in the context file rather than
writing an empty one.

These two files, the context file, and the skill's own report are the only files a review
run creates.

### The context file

Write it once, at the path the plan names, after the patches and before launching anything
(on a fix, before the premise pass too). Every agent prompt then carries its **path** instead of a retyped
paragraph: prompts drift apart when the context is inline, and a correction reaches only
the agents launched after you found it.

It opens with this framing line, verbatim, so every pass judges against library stakes:

> This is framework / library code: its consumers are arbitrary downstream applications,
> its observable behavior is a contract, and it is maintained for years — judge it
> accordingly.

It holds: branch, the literal `base` and `head` SHAs, the two patch paths with the note
that **the patches are the diff under review**, `git diff --stat`, the changed-file list
split into prod and test, the type and its signal, the scale tier with counts and any override, PR title/body when a PR exists, a
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

Then **quote those chapters here, in full**, under `### Conventions excerpt`. The
fit pass otherwise reads the whole conventions doc — most of which governs code
this diff does not touch — and on a fold row the general pass reads it a second time. Head
the excerpt with this instruction, verbatim:

> These are the conventions chapters that govern this diff. Do not open the conventions doc
> unless a finding of yours needs a rule that is not quoted here; say so in the finding if
> you had to.

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
the context file path, the pass's `reads` lane resolved to the patch path(s) it names, the
pass's `folds` and `prompt adds` from the plan, and [`delivery.md`](delivery.md)'s delivery
clause verbatim. Questions, categories, output
contracts and verification rules live in the agent definitions (`agents/<name>.md`) — never
paste them into a prompt.

**A fold widens the lane.** A pass reads its own `reads` lane *plus* the lane of every pass
folded into it — so `general+fit+tests` gets the test patch too, and
`general+…+slop` gets the `comment_files` list. Name those extra inputs in the prompt; a folded question with no
material is a silently dropped pass.

Read [`delivery.md`](delivery.md) before the first launch and follow it exactly: it is what
decides whether findings arrive at all. Its waiting rule applies here — pre-verify the
claims you expect while a batch is in flight, never poll.

### Read discipline

Copy this block into the context file **verbatim**. Every pass in the batch is reading the
same branch, so an unbudgeted read is paid for once per agent, not once:

> - **The patch named in your prompt is your diff.** Read it once. Do not run `git diff`,
>   `--stat`, `--numstat` or `--name-only` yourself — the plan already resolved them and
>   they are in this file. Do not read a patch your prompt did not name: another pass owns
>   that lane and reports on it.
> - **Open a whole file only when the hunk plus its ten lines of context genuinely cannot
>   answer the question**, and say which file and why in the finding. `git show
>   <BASE>:<path>` to check pre-change behavior is the case that qualifies; re-reading the
>   post-change file you already have as a hunk is not.
> - **Never re-derive a Settled fact or a Conventions excerpt.** Both are quoted in this
>   file precisely so no agent spends a call on them.
> - **Search once, narrowly.** Grep the touched packages and their siblings, not the repo,
>   unless a claim depends on repo-wide absence — then say that is what you searched for.

**Fallback**, only when the plugin's agents are unavailable: use `general-purpose` and paste
the body of the corresponding `agents/<name>.md` into the prompt.

Findings come back one per line:

```
<category> | <file>:<line> | <A|B|C> | <claim>
```

Categories: `general`, `scope`, `intent`, `requirements`, `premise`, `root-cause`,
`behavior`, `integration`, `tests`, `slop`, `cleanup` — plus `architecture`, `boundary`,
`impact` and `api` when arch-review's lenses ran. **A category is not a pass**: `fit`
reports `intent`, `scope`, `integration` and `cleanup`. The roll
call goes by pass, the report by category.

### The premise gate — fix only

The premise pass answers one question: **does the project already have a decision about
this behavior?** A bug fix can be right in every detail and still be the wrong fix.

- **No decision found** → `premise: unverified`, continue.
- **Decision agrees with the fix** → `premise: sound` with the citation, continue. Append
  its citations to the context file's **Settled facts** before launching the batch, or every
  later pass re-derives them. Append its **suite search** too — the existing tests it found
  that touch this behavior, by name and path — whatever the verdict: that is the search the
  root-cause pass would otherwise repeat to answer "is there a regression test".
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
3. **Judge, then tier.** Per finding, one sentence of judgement first — does the evidence
   hold, and what does the issue cost if the change merges as-is — then the final tier per
   [`severity.md`](severity.md), overriding the agent's proposal: the judgement is the
   reasoning, the tier is the conclusion. Where an agent overstated a claim, keep the
   corrected version and say so in one clause.
4. **Write the suggested fix as one line.** Concrete and specific to the file and line: "move
   the listener removal into `disconnectedCallback`", never "consider refactoring this".

Wording, because the report and any comment reuse these lines verbatim: every identifier,
method, type and compared literal in backticks; plain developer words, no invented labels;
one short sentence per claim, keeping the single detail that makes it concrete. Assume the
author knows the code: name the trigger only when it is not obvious, do not explain
consequences the reader can infer, and do not re-tell the trace that produced the finding.
Length is not thoroughness.

## 6 — Deliver

The skill's own step. Nothing in this pipeline edits code, stages, or commits; the one
carve-out anywhere in the plugin is self-review's coverage stage, which restores every
mutant before the next.
