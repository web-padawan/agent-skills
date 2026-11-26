# Lessons of the review skills

Each line is a lesson that a real review run measured. The run is named in brackets. Its
entry in [`retrospective.md`](retrospective.md) holds the numbers. No skill loads this file.
Read it before you add a mechanism, and before you drop a rule that looks like ceremony.

## Inputs

- **Prepare the inputs once.** A script writes the diff, CI, the threads, the conventions and
  the commits into one context file. Passes that derive them again pay for each read
  (PR review 2, 2026-09-08 accounting).
- **The dominant cost is passes times diff.** Each pass reads only its own lane of the diff.
  Only the tests pass reads both lanes (2026-08-27).
- **Never Edit the context file.** Edit needs a Read, and the Read pulls the diff into the
  orchestrator. The orchestrator puts its facts into the prompts (2026-09-08 costs).
- **The plan is the launch.** The plan prints literal prompts, SHAs and paths. No run
  derives a launch from prose, so every run has the same prompts (2026-09-08 costs).
- **Quote the conventions docs whole.** A selection of chapters lost a rule of the form "when
  you add X, also update Y". The CI bot applied that rule (2026-11-02 comparison).
- **A fact in the plan beats a rule in a doc.** Passes missed rules that lived in a guideline
  or in their own checklist. They found them when the plan named the line (fork dry run).
- **CI is authoritative.** A green check retires its class of finding. A red lint or test
  check is an A. An advisory check, such as a duplication gate, is not an A (PR reviews 1, 15).
- **Existing threads are a filter and a recall source.** Six of 9 findings of one review were
  already on the PR. A bot claim can be false, so triage verifies an open thread (PR reviews
  4, 7).
- **Size is a proxy for risk.** A risk override raises the scale tier. The tier counts
  production files and lines, never test files (PR reviews 2, 14).

## Gate

- **Decide before you review.** On fork PRs, the most expensive maintainer work was the
  question "should this exist?". Explain the PR and ask before any pass runs (fork dry run).
- **Keep a cheap path.** Reviewers picked the single-context review at 9 of 23 gates. It
  found a blocking issue without a subagent (log audits).
- **The question carries its content.** The open dialog can hide the text above it. A
  reviewer answered a gate without the explanation (PR reviews 16 to 19).
- **The screening flags are facts, not a verdict.** A verdict hint fired twice in 23 gates,
  and both times it was wrong (log audit, part 2). The flags:
  - `behavior-altering` is a semver call.
  - `feature-no-ac` holds a contributor to the PR template. A team author takes a feature
    from the backlog, so the flag skips a team author.
  - `low-impact`: a low impact issue rarely justifies a change to a module that many
    packages import.
  - `a11y`: a change with a wide reach needs a test with a screen reader, which no pass runs.
  - `untriaged` or `self-filed`: no team member confirmed the bug. A team author who files
    an issue is that confirmation.

## Passes

- **Split the passes by question.** What the change does, how the code is written, and
  whether the tests pin it. Sixteen lens agents reported the same 2 A findings many times
  (2026-08-27).
- **Never name an agent.** A named agent ends its turn idle, and its report does not return
  (2026-09-08 costs).
- **A lost report looks like a clean pass.** Count the reports before triage. Launch a pass
  again once when it returned nothing (2026-08-27).
- **The passes never learn the bar.** A pass that knows which tiers post drops a borderline
  finding. Triage alone filters (2026-11-02 comparison).
- **A Settled fact states only the fact.** A directive in a Settled fact made two passes
  report the gap that it named (PR review 14).
- **Verify a fact before it becomes a Settled fact.** A CSS inference across themes went in
  without a runtime check, and it was false (PR review 12).
- **A Settled fact must not invite challenge.** "Do challenge" made 3 of 4 agents derive the
  fact again (2026-08-27).
- **One lead, one owner.** Every pass verifies a lead that has no owner. An owned lead ends
  as a finding or as a `lead cleared:` line (PR review 4).
- **One round does not find everything.** A second round on the same head found 61 new
  findings after 92, and 19 of them were B (2026-11-02 loop dry run).
- **Findings come first in the output.** A long result is cut from the end (PR review 3).
- **Anchor a finding at its declaration line.** Two passes then land on the same line, and
  triage matches them without work (PR reviews 3, 8).
- **An agent handed a list writes a survey.** Give a pass questions, not a list of changes
  to describe (2026-08-27).

## Triage

- **A wrong comment costs more than a missed issue.** Verify every kept claim. An unverified
  claim posts as a question.
- **A claim about code outside the hunk needs `src:`.** Every finding with a cited source
  line was right in the docs dry run. Both partly wrong findings had no source (2026-11-03).
- **Running the code beats a second read.** A browser probe removed a false A and found a
  real B in the same review (PR review 12).
- **Drop what the author cannot act on.** That is rigor that the codebase does not follow,
  pre-existing issues, process questions and pins of vendor defaults (PR reviews 7, 11, 14,
  20).
- **A finding that reverts a commit of the branch is intentional by default.** A posted
  suggestion reversed a commit of the author and was retracted (PR review 5).
- **The tier is not the comment.** A/B/C is the scale of the plugin. A reader gets a
  Conventional Comment with the same meaning (PR review 1).

## Posting

- **Post one review.** One comment per finding sends one notification per finding
  (2026-11-02 comparison).
- **Check every anchor and the head before you post.** A line outside the hunks moves the
  thread to the file. A moved head makes a finding stale (PR reviews 10, 16 to 19).

## Safety

- **A fork head is untrusted.** Never check it out, and never run its code. A PR controls
  the hooks and the `CLAUDE.md` of its checkout (2026-11-03).
- **Frontmatter does not restrict Bash.** `tools:` patterns did not stop a write in a probe.
  A hook holds the passes to read commands (fork dry run).

## Process

- **A mechanism needs a second occurrence.** Two prunes removed 11 mechanisms. One incident
  had added each of them (log audits).
- **Measure a mechanism before you keep it.** Count how often it fired and whether it changed
  a posted finding. The log audits did that from the session logs.
- **A file that must exist at the right moment breeds fixes.** The notes file of the
  orchestrator caused 6 incidents in 3 months. The facts now travel in the prompts (log
  audits).

## Tried and removed

Do not add one of these again without new evidence.

| Mechanism | Removed | Evidence |
| --- | --- | --- |
| Sixteen lens agents | 2026-08-27 | same 2 A findings reported many times |
| A chapter selection of the conventions doc | 2026-11-02 | lost a rule that the CI bot applied |
| `post-review.sh --blocking-only` | 2026-11-24 | chosen 0 times at 21 post gates |
| `pr-refresh.sh` at the gate and at triage | 2026-11-24 | 1 change in 35 runs |
| `workflow-facts.sh` | 2026-11-24 | no workflow PR after it landed |
| The deep candidate count | 2026-11-24 | printed 0 for 106 new Java methods |
| The `type_conflict` signal | 2026-11-24 | `none` in 37 of 37 plans |
| Ids in the notes file and a `notes:` line per pass | 2026-11-24 | no guard denial, no changed finding |
| Reconcile of earlier findings on a newer head | 2026-11-24 | 0 of 14 plans ran on a newer head |
| The stage registry and slots | 2026-11-24 | 2 stages for 1 skill |
| The escalation ladder for lost reports | 2026-11-24 | 0 lost passes in 22 roll calls |
| Screening verdicts and `Draft a reply` | 2026-11-26 | 0 replies drafted, 2 wrong hints |
| The Follow-ups section of the self-review report | 2026-11-26 | a copy of every B and C finding |
| The coverage check by mutants | 2026-11-26 | the tests pass already had 15 of 17 survivors |
| The failing test step of pr-review | 2026-11-26 | 0 runs after it landed |
| The findings file of self-review | 2026-11-26 | each use was a second round in one session |
| The notes file and `notes-guard.py` | 2026-11-26 | 6 incidents in one mechanism |
| Deep blocks, `BELOW LINE` and the deep budget | 2026-11-26 | a block holds no finding of its own |
| `pr-refresh.sh` | 2026-11-26 | `post-review.sh` caught both incidents behind it |
| `related-prs.sh` | 2026-11-26 | one incident, no use after it |
| The code pass on a same-repo PR | 2026-11-26 | 4 of 44 posted threads |
| The smell vocabulary | 2026-11-26 | every reviewed repository has a conventions doc |
| `docs/contracts.md` | 2026-11-26 | the plan keys moved to `review-plan.sh --help` |
