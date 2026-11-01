# Retrospective — what the runs taught

History, for people. No skill, agent or script loads this file; the rules it produced live
in the reference docs, and [`rationale.md`](rationale.md) lists the principles in one line
each. Every entry here is a real run: what it was, what it cost, what it exposed, and what
changed because of it. Newest at the bottom.

## Before the pipeline had a shape — the early self-review runs

- **Deep review as a fan-out.** A fix branch reviewed with the old full profile ran 16 agents
  and reported the same two A findings from two and three lenses each, in a 1000-line report
  whose findings were 60% about code the accepted fix did not contain. The lens agents read
  the same change, ran the same consumer grep, and their convergence was cost deduped at
  triage, not signal.
  → The three lens agents became one change pass; deep review is a budget inside it, and a
  disagreement between the boundary and impact questions still surfaces as two finding lines
  from one agent.
- **A ledger that invited challenge.** A settled-fact ledger headed "do not re-derive, *do
  challenge*" was re-derived from source by three of four agents. The invitation licensed the
  spend: a sceptical reading of a settled fact costs as much as establishing it.
  → The Settled facts header says the entries are authoritative and a disagreement is a
  one-line finding, not a re-investigation.
- **Unowned leads.** Three leads handed to four agents without an owner produced four
  independent verifications of one non-issue — the single largest waste in that run.
  → One lead, one owner pass; other passes do not investigate a lead they do not own.
- **Clustering before ranking.** A four-file feature in one module is usually one decision,
  so one block. When the blocks ran as agent trios, getting it wrong cost full agent runs.
  → The change pass clusters candidates before it spends its block budget.
- **An agent handed a list writes a survey.** Measured on the lens agents; still the open risk
  of a change pass that selects and block-reviews changes itself.
  → The hedge is the block format, the small budget, and checklist-before-blocks ordering.
  The fallback, if surveys appear, is a change pass per named change.
- **Agents × diff, not agents.** Eight passes each ran their own `git diff` and paid for
  every line of the branch eight times — the test hunks, usually most of the branch, were paid
  for by seven passes that do not review tests.
  → Two prepared patches and a `reads` lane per pass; only the tests pass, whose coverage
  question spans both, reads both.
- **Four passes, one assertion question.** Four passes read the test diff to ask four
  overlapping versions of "does this assertion pin the right thing".
  → The tests pass owns every assertion question and is the only pass that opens the test
  patch. Overlapping questions are worth debating; overlapping reads were the cost.
- **Naming the conventions doc was not enough.** The code pass read all of it, most of which
  governs untouched code.
  → The governing chapters are quoted into the context file, the way Settled facts are.
- **Seven breadth agents were one checklist read seven times.** The type-specific passes
  (requirements, fix, behavior) and the split of the general questions across general, fit
  and slop all judged the same production patch against the same reference material; triage
  spent its budget deduping findings the batch had paid to produce twice.
  → The checklist splits along the one seam where the *searches* differ: what the change does
  and promises (the pass that greps consumers) and how the code is written (the pass that
  sweeps siblings). The type reaches the first as a prompt add; the second is type-agnostic.
- **The escalation ladder's first rung was unreachable.** It pinged a named agent, and the
  launch rule forbids `name`, so every lost report wasted a turn before the re-spawn.
  → The rung is gone; the ladder starts where the launch rule leaves you.

## A self-review of a styling-only fix — six gaps at once

A CSS fix with regenerated screenshot baselines.

- Binaries sat in the patch as `Bin N -> M` stubs — noise — and dropping them would have left
  no pass able to ask whether the baselines were regenerated.
  → The `binary_files:` lane: named, never diffed.
- The squashed `base..head` diff hid that the fix landed *after* the commit that captured the
  baseline. A stale baseline and a `test:` before its `fix:` are only visible in commit order.
  → `commits:` in the plan and the skeleton.
- The type × scale matrix budgeted 15 mutants for a diff with zero mutable lines.
  → The advisory `mutant_pool:`.
- The chat gate said `8 C` and the report `10 C`, each derived separately from the agent
  reports.
  → The frozen list: one canonical list that every rendering reads from.
- Follow-ups repeated every B/C finding with its fix and became a third of the report.
  → The index.
- A report full of `confirmed` never said *how*, indistinguishable from taking the agents at
  their word.
  → `— verified: <how>` on every confirmed finding.

## PR review 1 — a 6-file, 50-line CSS fix with 18 baselines

Cost: 265k subagent tokens across three passes; the change pass alone 58 tool calls over
17 minutes, two of which mattered.

- The code pass copied three files to a scratchpad to run prettier and prove there was no
  lint failure, on a PR whose Lint check was green. The change and tests passes both reasoned
  about whether the baselines were stale, on a PR whose Base, Lumo and Aura visual checks were
  green. `gh pr checks` answers all of it in one call and no script was making it.
  → `=== CI_STATUS ===`, the plan's `ci:` digest, and severity.md's rule that a green check
  is authoritative.
- Nothing sized a pass; scale capped only mutants and deep blocks.
  → `effort_per_pass:` and a drop order in every agent definition.
- The one finding no pass produced came from decoding PNG headers by hand: `394x52 ->
  394x45` said an element lost 7px, and three baselines came back `size unchanged`, meaning
  content moved inside a box that did not — the fix's own signature, invisible in a byte
  count.
  → `binary_dims:` — image dimensions before and after, next to each binary file.
- Two posted comments fell back to general comments because their files were not in the diff,
  discovered *after* the user had approved posting.
  → The anchor check at triage step 5.6.
- The verdict printed `Looks good` over a confirmed finding that the fix never reached one of
  three released themes: the A/B tie-breaker ("can a follow-up PR fix this?") always answers
  yes for a released sibling and had quietly deleted the blast-radius rule.
  → The tie-breaker never overrides an explicit type-aware A, and any confirmed `issue`
  moves the verdict.
- The run wrote a 50-line prod patch to its own file and every pass paid a second read for it.
  → Below ~300 lines the diff is inlined in the skeleton.
- Posted as `[B: follow-up]`, a finding told a PR reader nothing they had words for, and an
  unverified claim capped at B still posted as an assertion.
  → Conventional Comments: the tier decides the label (`issue` / `suggestion` / `nitpick`),
  the decoration says `blocking` or `non-blocking`, an unverified claim becomes a `question`
  worded as one, and a call that is not a code reviewer's to make routes as `question
  (a11y|design|semver|flow)`. The label is frozen with the tier, for the same reason the tier
  counts are. `post-comment.sh` enforces the closed vocabulary. Borrowed from USWDS's review
  skill and the Conventional Comments spec.

## PR review 2 — a 6-file, 115-line combo-box fix (89 production lines)

Cost: ~157k subagent tokens for 12 findings, of which the pr-mode filter kept one B
suggestion, one C nit and a praise. Where the tokens went, from the transcripts:

- The orchestrator-written context file was 35k chars, read three times (~29k tokens).
- The change pass spent ~22k output tokens, 5.7k of them on three deep blocks that yielded a
  praise, because 115 total lines had tipped `lite` (≤100) into `full` with deep 3 and a
  60-call ceiling no pass came within 50 calls of — so nobody economized.
- Both the change and code passes re-read `setProperties` and the whole head mixin file that
  the context file already quoted as Settled facts and -U10 hunks. Re-reading lines the
  context file already quoted was the single largest waste in both transcripts.
- Nine of the twelve findings were C, requested by a "C findings are wanted" rule copied
  verbatim into a mode whose filter drops them by design.
- The orchestrator read five procedure docs (~9k tokens), CONVENTIONS.md in full to quote 400
  words, fetched the PR body twice, re-typed five verbatim rule blocks, and after fan-out
  appended notes nobody read — every pass reads the file once, at launch.

What changed:

- The C rule is mode-variant: `c-rule-pr` asks for C only against a quoted convention.
- Scale is sized by production lines, `lite` at 150; the deep budget is capped by the
  `deep_candidates` the script counts, so a fix with no public surface gets one block; the
  effort ceilings are 10/20/30.
- The plan script writes the whole deterministic skeleton — rules and rubric extracted by
  `<!-- block:… -->` marker, PR body, lanes, inline diff, conventions chapters selected by
  touched file kinds and the signals in the added lines, CI — and the orchestrator adds only
  Settled facts it verified and Open leads.
- A small file touched in several places is quoted whole once; the test diff runs at -U15 so
  the `beforeEach` is in view; every agent checks the context file before opening a file and
  returns no narrative around its finding lines.
- The wait after fan-out is spent only on what the passes cannot reach — an external repo, a
  parent issue — never on the files they are reading at the same moment.

## PR review 3 — the losses after the passes returned

- The change pass's result came back cut behind a `[result truncated …]` marker, and the
  truncated tail was its deep blocks, because the findings sat behind prose.
  → Output contracts put findings first; delivery.md has a truncation rung that reuses the
  live channel and a `⚠️ truncated` roll-call mark.
- The same defect reached two passes at different anchors — one on the enclosing block, one
  on a range — and triage matched them by reading.
  → The declaration-line anchor: two passes on the same defect land on the same `file:line`.
- Verifying had no ceiling of its own and re-read what the passes had read.
  → The triage ceiling table, and the note that a browser probe settles a CSS claim that
  re-reading cannot.
- Every forced completion turn restated the pass's brief.
  → One status line in the roll call's vocabulary, nothing else.
- `pr` mode's default report dir pointed inside the repo, for a record the skill says is never
  committed.
  → `SCRATCHPAD` by default and a `pr-<n>-REVIEW.md` report path.

## What the three PR-review bills said together — the fixed costs

- Every pass ran on the orchestrator's model, because no agent definition named one, and two
  of the three are checklist sweeps over a diff the skeleton already quotes.
  → profiles.md's `Pass model` table — opus for the change pass at every tier, sonnet for the
  other two below `full` — read by the script and printed in each prompt's header.
- Every launch was assembled from five parts read out of three documents.
  → `=== PROMPTS ===`: the literal prompt per pass, with the delivery clause copied from
  delivery.md by marker, so the prompts are word-for-word the same from run to run.
- Appending to the skeleton needed Edit, Edit needs a Read, and that Read pulled the inline
  diff into the orchestrator's context — the one cost the skeleton was written to remove.
  → The `notes:` file, created once with Write and read by every pass after the skeleton.
- "The context file already holds it" stood in the skeleton three times and in every agent
  definition twice more, paid for by each agent on both reads.
  → It lives in the skeleton's read-discipline and rubric blocks alone.

## PR review 4 — the review that was already on the PR (web-components #12590)

A 33-file, 126-production-line feature with 40 new visual baselines, reviewed forty minutes
after a review bot had left four inline comments and the reviewer five more.

Cost, from the transcripts: change pass 17 calls / 33.5k output tokens, code pass 17 / 33k,
tests pass 10 / 10.6k. The skeleton was 500 lines; the plan output 30KB, which the harness
persisted to a file, so the orchestrator read it three times.

- Six of the nine findings offered at the gate were already on the PR — three matched the
  bot, three the reviewer's own comments. `Yes — post all` would have doubled the author's
  reading for nothing. Nothing in the pipeline fetched existing comments.
- The one bot comment none of the three passes reproduced was a real conventions gap: two new
  public CSS properties absent from every component's styling table. The existing comments
  were a recall source, not only a duplicate filter.
  → `=== EXISTING_COMMENTS ===` (thread roots with their resolved state, one GraphQL call),
  the skeleton's `## Already on the PR` section, the `dup:<id>` tag on a finding line,
  triage's `already raised` status with a `confirms` / `contradicts` verdict, a gate that
  never offers a match as a new comment, and `post-comment.sh` refusing to open a second
  thread within two lines of an existing one. The bot's claim is not authoritative — the pass
  still reads the diff — only its existence is.
- Why the missed finding was missed: the orchestrator had written it as an Open lead owned by
  the change pass ("check the `.d.ts` and JSDoc styling docs describe them"). The pass ran two
  greps toward it and never reported a verdict, and the output contract had no slot for one,
  so the lead vanished between the notes file and triage.
  → The `lead cleared:` line: every owned lead ends as a finding or as one line saying how it
  was closed, and a lead that ends as neither is triage's own work.

## Context accounting after run 4 — where a run's fixed tokens go

Measured on the #12590 artifacts (chars ÷ 4 ≈ tokens).

What the orchestrator loads:

| Item | Size | Notes |
| --- | --- | --- |
| pr-review SKILL.md | 13.5KB | injected at invocation |
| plan output | 34KB | above the ~20KB inline limit, so persisted and read up to three times |
| pipeline.md + severity.md + delivery.md + comment-guidelines.md | 31KB | read on demand |
| rationale.md | 16KB | linked from self-review; nothing in a run needs it |

Inside the plan output: `=== ANCHORS ===` 10.8KB (every changed path, then the diffstat
repeating every path — both already in the plan's `prod_files` / `test_files` /
`binary_files`), `binary_dims:` 4.3KB (40 lines of `absent -> WxH`, every one a new file),
the `passes:` table's prompt-adds column (already the literal `=== PROMPTS ===`).

What every pass loads — the skeleton, 41KB, read three times per run:

| Section | Size | Notes |
| --- | --- | --- |
| Conventions excerpt | 12.4KB | six chapters selected by `css src types events test` |
| Changed files | 10.6KB | three lane lists, then a diffstat repeating every path |
| Settled facts | 5.1KB | 4.4KB of it the image table — 40 long paths a second time |
| Severity rubric + Rules | 5.0KB | agent-facing blocks, fixed |
| Already on the PR | 3.3KB | new in run 4 |

What changed:

- The plan echoes only the context sections the orchestrator uses — PR metadata, CI, existing
  comments — plus any `error:` line from the rest; `binary_dims:` prints a digest and only
  the resized or same-size images; the `passes:` table lost its prompt-adds column. The
  #12590 plan output falls under the inline limit.
- The skeleton lists each binary file once, with its dimensions beside it, and carries the
  diffstat's summary line instead of the table.
- The agent-facing blocks moved out of pipeline.md and severity.md into `skeleton-blocks.md`,
  which only the plan script reads; the rubric block stays in severity.md because triage
  needs it too.
- rationale.md keeps one line per principle; the measurements live here, unloaded.

Still open, not changed:

- The conventions excerpt is 30% of the skeleton. `dev/baseline.html` counts as a production
  file and its `addEventListener` selected the Events chapter for a styling PR; the excerpt
  chapters are whole. Selecting by hunk rather than by file kind, or excluding `dev/` from
  the signals, would cut it — but the excerpt exists because the code pass reading the whole
  doc cost more, so measure before cutting.
- The seven skill descriptions total ~4.7KB and ride in every session's system prompt where
  the plugin is installed. Shorter descriptions are a triggering question for
  `authoring-skills`, not a pipeline one.
- The `pr-review` SKILL.md is 13.5KB and its step 1 enumerates every plan line the script
  already labels. Cheap to cut, but the enumeration is what tells a first-time reader which
  lines to act on.
