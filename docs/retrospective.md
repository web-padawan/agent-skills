# Retrospective

What each real review run exposed, and what changed because of it. Newest first. Each bullet
reads `what the run showed → what changed (commit)`. No skill, agent or script loads this
file. The principles are in [`rationale.md`](rationale.md), one line each.

## 2026-11-04 — Fork PR dry run: 11 web-components PRs from forks

The bot skips forks, so the maintainers reviewed alone. Each PR ran at its pre-review head,
with labels, body and comments replayed to the first maintainer comment. 33 passes, no
code of a head ran. Ground truth: 23 maintainer findings (`.omc/plans/fork-pr-corpus.md`).

- Two of 11 merged as written. The costliest maintainer work was the question "should this
  exist?", and no pass read the linked issue → `pr-intake.sh`: issue labels as of a time,
  import reach, Flow counterpart, a verdict hint (`8b49a3f`, `2f1fd81`).
- The hint said `decide` on #12970, #12976 and #13316, the three PRs that stopped at a team
  decision, and on no other PR. #12974 got `take`, because its `behavior altering change`
  label came 16 days later. Its change pass raised the semver question anyway.
- An audit read the current state of the PR: later labels, rewritten bodies, review threads
  → `--head` and `--as-of` (`a0f1921`).
- A fork head had no guard and the passes had unrestricted Bash. `tools:` patterns in agent
  frontmatter did not restrict Bash in a probe → a fork guard in the plan and a PreToolUse
  hook that holds the reviewer passes to read commands (`2f1fd81`, `da91ad6`). Verified live.
- `pr` mode muted `reuse`, the class of two maintainer findings → a fork PR keeps it
  (`5a6b572`). The code pass then found the dead `readyState` check of #12975.
- Recall 15 of 23. Misses: CSS unit tests, a new suite, a shadow DOM reach
  → `css_rule`, `new_test_files`, `shadow_reach` facts (`2e27fc3`, `1ca6311`, `c5a98be`).
  A re-run found all three, two of them only as C → a rule-backed finding is B
  (`e74f151`). Recall after the re-run: 19 of 23.
- Still missed: the Flow synchronous data provider (#12969), the `_onInput` location
  (#12969), the offset API (#4565, #12976) and the component JSDoc (#12976).
- New true findings, by a read: #12975 leaves `uploading: true` after an abort (still on
  `main`), and #13316 misses the notification container. One A of 9 was false: a stale
  snapshot claim on an overlay that keeps its own role.
- One skill for a PR of someone else: `guided-review` merged into `pr-review`, with an intake
  card and a gate before the fan-out (`fb20382`).
- Cost: about 3M subagent tokens for 36 passes. The longest pass took 6 minutes.

## 2026-11-03 — Docs profile for the Vaadin CI code review: dry run on vaadin/docs #6526, #6495, #6535, #6544

The shared action got `review-docs.md`, with the judgement-before-value step of `review.md`.
One independent agent per PR verified every finding against the product checkouts.

- 16 posted findings: 14 true, 2 partly true, 0 wrong. Every finding with a cited source
  `file:line` was right. Both partials were strong wording with no cited contradiction →
  `src:` on the finding line (`841c2f6`).
- 4 of 16 tiers one level too high → a docs rubric that maps value to A / B / C (open: item 4
  of `.omc/plans/review-followups.md`).
- The precision of this plugin was never measured → a verification audit (the 2026-11-04
  fork dry run above is the first).
- A live run on #6544 matched 2 of 3 dry-run findings on the same head, one new, one gone →
  `--rounds 2` on a full docs review (open: item 4).
- The author agent fixed 3 findings within 12 minutes. Cost about $4.80 and 5 to 11 minutes
  per review, against 3 to 4 minutes per round here.
- On 60 docs PRs, word lists found 3 AI-tell words. Density did the work: 2.3 times the
  cross references, 3 times the parentheticals per sentence → `prose_density:` (open: item 7).
- A PR controls hooks, `.mcp.json` and `CLAUDE.md` of its checkout, and read-only
  commands have side-effect flags → `fork:` and a guard (`2f1fd81`), a Bash guard (`da91ad6`).

## 2026-11-02 — Self-review loop dry run: web-components #13301, #13312, #13313, #13335

Prompted by GitLab Duo Code Review, which reruns until nothing is left. Two rounds of the three
passes on four unchanged pdf-viewer feature heads.

- Round 2, given round 1's findings and told to sweep hunk by hunk, found 61 new findings
  after 92 (19 B). Three spot-checked B were real → rounds budget, `rounds` column and
  `--rounds N`; a repeat round lists earlier findings as reported (`02bc32f`, `0f89556`).
- Every fix cycle started from zero → `<branch>-findings.json`, read by the next plan: same
  head is a further round, a newer head is reconciled with Duo's statuses and C findings only
  on lines changed since, a rewritten head is reconciled without markers. `disputed` never
  returns (`2a2dd3b`, `1c4164f`).
- Passes stopped after their first findings in a file → hunk-by-hunk rule in all three agents
  (`5eae87a`, `f66fa46`, `f039ad6`).
- Round 1 re-raised a thread the author had dismissed, tagged as a dup. Round 2 did not.
- Cost: 24 opus passes at ~75k tokens each, 3 to 4 minutes wall clock per round.
- Open: passes that review a worktree run git in the wrong repo until a notes line names the path.

## 2026-11-02 — Comparison with the Vaadin CI code review (vaadin/github-actions code-review)

Its bot caught both #10519 omissions. The differences that explained the misses:

- Passes knew that PR mode drops C and self-censored. Upstream never tells the agent the bar
  → one C rule for both modes (`7c53b36`).
- Chapter selection lost a "when you add X, also update Y" rule. Upstream reads the whole doc
  → the conventions doc is quoted whole up to 400 lines (`794610d`).
- Only thread roots were read, so author dismissals were invisible → reply lines, `dismissed`
  and `not fixed` statuses (`637afcb`, `be8c18a`).
- One comment per finding meant one notification each, with no file-level anchor →
  `post-review.sh`: one pending review, line then file then body anchors (`f2983cd`).
- No check for unregistered handlers, one-sided paired operations or missing API docs →
  code-reviewer checklist items (`2cf2af9`).

## 2026-11-02 — PR review 5: flow-components #10519, PDF viewer Flow wrapper

Cost: ~161k subagent tokens across three passes.

- An unused `CompletableFuture` release in a test fixture went unreported: infrastructure was
  capped at C, and PR mode dropped C → fixture economy checks (`d461257`).
- A posted suggestion contradicted CONVENTIONS.md and reversed the author's own commit, so it
  was retracted → conventions check before calling a test redundant (`d421b17`); a finding
  that reverts a branch commit is intentional by default (`1e7629b`).
- The CI bot found two omissions: no `osgi.bundle.license` and no `REACT_COMPONENTS` entry.
  The change pass had cleared registration after grepping one sibling for its artifact id →
  the plan detects a new unit and lists registration and scaffold gaps from its siblings, and
  build files select conventions chapters (`e7631d7`, `7f63338`). On #10519 each check
  returned exactly the bot's finding. On #9379 it found the BOM miss fixed later in #9542.

## 2026-09-08 — Context accounting after PR review 4

- Plan output was 34KB, over the inline limit, and read three times → the plan echoes only PR
  metadata, CI and existing comments, and `binary_dims:` prints a digest (`63c90e3`).
- The skeleton was 41KB, read three times per run, with every path listed twice → each binary
  once with its size, and the diffstat's summary line only.
- Agent-facing blocks sat in docs that triage also reads → moved to `skeleton-blocks.md`.
- Left open then: the conventions excerpt was 30% of the skeleton. Superseded on 2026-11-02,
  which chose recall and quotes the whole doc.

## 2026-09-08 — PR review 4: web-components #12590

33 files, 126 production lines, 40 new baselines. Cost: change 17 calls / 33.5k output tokens,
code 17 / 33k, tests 10 / 10.6k.

- 6 of 9 gate findings were already on the PR → `=== EXISTING_COMMENTS ===`, `## Already on
  the PR`, `dup:<id>`, `already raised`, and a nearby-thread guard in `post-comment.sh`
  (`3a5a30f`).
- The one bot finding no pass reproduced was real → existing comments are a recall source too.
- An owned lead vanished without a verdict → the `lead cleared:` line.

## 2026-09-08 — Fixed costs across PR reviews 1 to 3

- Every pass ran on the orchestrator's model → `Pass model` table (`7f1328d`).
- Every launch was assembled from three docs → `=== PROMPTS ===` with literal prompts.
- Appending to the skeleton pulled the inline diff into the orchestrator → the `notes:` file.
- "The context file already holds it" was repeated in five places → the read-discipline block only.

## 2026-09-07 — PR review 3

- The change pass's output was truncated and lost its deep blocks → findings first in every
  output contract, a truncation rung, a `⚠️ truncated` mark (`3199934`).
- Two passes anchored one defect differently → the declaration-line anchor.
- Verification had no budget → the triage ceiling table.
- Completion turns restated briefs → one status line per turn.
- PR-mode reports defaulted into the repo → `SCRATCHPAD`.

## 2026-09-07 — PR review 2: a combo-box fix, 89 production lines

Cost: ~157k subagent tokens for 12 findings, of which the PR filter kept 1 B, 1 C and a praise.

- A 35k-char context file was read three times, and passes re-read quoted code → the plan
  script writes the whole skeleton, plus the read-discipline block (`5db5132`).
- 115 total lines tipped `lite` into `full` → scale by production lines, `lite` up to 150,
  deep budget capped by `deep_candidates`, ceilings 10/20/30.
- 9 of 12 findings were C under a rule that the PR filter drops → `c-rule-pr`, replaced on
  2026-11-02.
- The orchestrator read five docs to quote 400 words of conventions → the script selects
  chapters.
- Notes written after fan-out reached nobody → the wait goes only to what passes cannot reach.

## 2026-09-04 — PR review 1: a 6-file CSS fix with 18 baselines

Cost: 265k subagent tokens. The change pass made 58 tool calls in 17 minutes.

- Passes re-proved lint and baselines that green checks already answered →
  `=== CI_STATUS ===`, and a green check is authoritative (`213d5bd`).
- Nothing sized a pass → `effort_per_pass:` and a drop order per agent.
- The key finding came from PNG headers decoded by hand → `binary_dims:`.
- Two approved comments fell back to general ones → the anchor check at triage 5.6.
- `Looks good` printed over a miss in a released theme → the tie-breaker never overrides a
  type-aware A, and any `issue` moves the verdict.
- `[B: follow-up]` meant nothing to a PR reader → Conventional Comments labels (`0684e31`).
- A 50-line patch was read twice → diffs under ~300 lines are inlined in the skeleton.

## 2026-08-27 — Self-review of a styling-only fix

- Binary baselines showed as `Bin N -> M` stubs → the `binary_files:` lane (`9ed129e`).
- The squashed diff hid that the fix landed after the baseline commit → `commits:`.
- 15 mutants were budgeted for zero mutable lines → `mutant_pool:`.
- Chat gate and report counted C differently → one frozen list.
- Follow-ups repeated every fix → an index only.
- `confirmed` never said how → `— verified: <how>`.

## 2026-08-27 — Early self-review runs: from 16 agents to three passes

- 16 lens agents reported 2 A findings several times each in a 1000-line report → one change
  pass with a deep budget (`571263a`).
- Settled facts headed "do challenge" were re-derived by 3 of 4 agents → Settled facts are
  authoritative.
- Unowned leads were verified four times → one owner pass per lead.
- Each pass ran its own `git diff` of the whole branch → two prepared patches and a lane per pass.
- Four passes asked overlapping assertion questions → the tests pass owns them.
- Seven breadth agents read one checklist seven times → split by search: change (consumers)
  and code (siblings).
- The escalation ladder's first rung pinged a named agent that the launch rules forbid → removed.
