# The review pipeline

Every review skill in this plugin runs the same six steps. A skill's SKILL.md holds only
what is different about it — this file is the shared part.

```
1 plan      run scripts/review-plan.sh — anchors, type, scale, budgets, pass list; writes the context skeleton
2 context   append Settled facts and Open leads to the skeleton — nothing else
3 fan out   launch the plan's pass list; delivery.md decides whether findings arrive
4 roll call delivery.md's roll call, then escalate anything that delivered nothing
5 triage    verify · dedup · tier · one-line suggested fix · label · freeze
6 deliver   the skill's own output: chat report, findings file, or PR comments
```

| Reference | Covers |
| --- | --- |
| [`profiles.md`](profiles.md) | The pass table, the type × scale matrix, the per-pass effort ceiling |
| [`severity.md`](severity.md) | A / B / C, the tie-breaker, type-aware tiering, the rendering table |
| [`delivery.md`](delivery.md) | Launch rules, the delivery clause, the roll call, the escalation ladder |
| [`rationale.md`](rationale.md) | Why the pipeline is shaped this way — measured, not guessed |

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
script can prove (CI digest, image dimensions), the conventions excerpt — chapters selected
by the kinds of file touched and what the added lines use — the severity rubric, the mode's rules, the read discipline and the scope rule.
**Do not re-quote, rewrite or re-derive any of it**, and do not read the conventions doc or
the diff yourself to check the skeleton — that is the spend the skeleton exists to remove.

You append three sections, in this order, and launch:

- **Settled facts** — facts you verified that a pass would otherwise derive: what a shared
  helper does, pre-change behavior, a consumer in another repo, a Flow connector's call.
  One line per claim with its evidence (`file:line`, a SHA, the command). Only what took you
  a call or two; the passes carry the budget for the rest.
- **Open leads** — suspicions you deliberately have not resolved. Every lead names exactly
  one owner pass (`[owner: change|code|tests]`); other passes do not investigate a lead
  they do not own, and triage inherits the owner's verdict.
- **Orchestrator notes** — only when the skeleton is wrong (a stale PR description, a
  mis-detected type). Notes appended **after** fan-out reach only re-spawned agents: every
  pass reads the file once, at launch.

### Blocks the script copies into the skeleton

Edit them here; the script extracts them by marker. The rubric and the mode rules live in
[`severity.md`](severity.md) the same way.

<!-- block:framing -->
> This is framework / library code: its consumers are arbitrary downstream applications,
> its observable behavior is a contract, and it is maintained for years — judge it
> accordingly.
<!-- /block -->

<!-- block:scope-rule -->
> Lines prefixed `+` in the diff are code the author HAS ALREADY WRITTEN — review their
> quality, never suggest implementing them. Only flag issues introduced by this change, not
> pre-existing code. When the Identity section says `checked_out: no`, read post-change file
> content with `git show <head>:<path>` (literal SHA), never from the working tree.
<!-- /block -->

<!-- block:read-discipline -->
> - **The diff section or patch named in your prompt is your diff.** Read it once. Do not run
>   `git diff`, `--stat`, `--numstat` or `--name-only` yourself — the plan already resolved
>   them and they are in this file. Do not read a patch your prompt did not name: another
>   pass owns that lane and reports on it.
> - **Before any `git show`, `sed`, `cat` or Read on a file, check whether this file already
>   quotes those lines** — the inline diff, a `### Full file` section, a Settled fact. Open a
>   whole file only when the hunk plus its context genuinely cannot answer the question, and
>   say which file and why in the finding. `git show <BASE>:<path>` to check pre-change
>   behavior is the case that qualifies.
> - **Never re-derive a Settled fact or a Conventions excerpt.** Both are quoted here
>   precisely so no agent spends a call on them.
> - **Search once, narrowly.** Grep the touched packages and their siblings, not the repo,
>   unless a claim depends on repo-wide absence — then say that is what you searched for.
<!-- /block -->

<!-- block:settled-header -->
> Each entry is authoritative. Do not open the file it came from. If a finding of yours
> depends on an entry being wrong, report that as a finding with your reasoning — one line,
> no re-investigation.
<!-- /block -->

<!-- block:conventions-header -->
> These are the conventions chapters that govern this diff, selected by the kinds of file it
> touches and what its added lines use. Do not open the conventions doc unless a finding of yours needs a rule that is not
> quoted here; say so in the finding if you had to.
<!-- /block -->

## 3 — Fan out

Launch the plan's `passes` list in **one message**, sharing one barrier. Each prompt is
exactly: the context file path, the pass's `reads` lane resolved to the section or patch it
names — for the code pass that is the prod lane *plus* the plan's `comment_files` list — the
pass's `prompt adds` from the plan, the plan's `effort_per_pass:` ceiling, and
[`delivery.md`](delivery.md)'s delivery clause verbatim. Questions, categories, output
contracts and verification rules live in the agent definitions (`agents/<name>.md`) — never
paste them into a prompt. Read delivery.md before the first launch and follow it exactly.

**Fallback**, only when the plugin's agents are unavailable: use `general-purpose` and paste
the body of the corresponding `agents/<name>.md` into the prompt.

Findings come back one per line:

```
<category> | <file>:<line> | <A|B|C> | <claim>
```

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
   category with a one-line pointer from the other.
3. **Your own findings count.** What pre-verification turned up and no pass reported goes on
   the list tagged `[orchestrator]`, held to the same verification bar.
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
   category, label, status, claim, fix, `summary-only`, and how it was verified when not
   obvious. Chat summary, tier counts, report and PR comments all render from it.

Wording, because the report and any comment reuse these lines verbatim: every identifier in
backticks; one short sentence per claim with the single detail that makes it concrete; assume
the author knows the code; do not re-tell the trace that produced the finding.

## 6 — Deliver

The skill's own step. Nothing in this pipeline edits code, stages, or commits; the one
carve-out anywhere in the plugin is self-review's coverage stage, which restores every
mutant before the next. The files a run creates are the context skeleton, the patch files
when the diff is too large to inline, and the skill's own report.
