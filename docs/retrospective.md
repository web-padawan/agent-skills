# Retrospective

What each real review run exposed, and what changed because of it. Newest first. Each bullet
reads `what the run showed → what changed (commit)`. No skill, agent or script loads this
file. The principles are in [`rationale.md`](rationale.md), one line each.

## 2026-11-10 — PR review 11: flow-components #10623, RTE Delta sync

One production file, `RichTextEditor.java`, 38 lines. The PR removes the private
`@Synchronize("value-changed")` getter `getDeltaValue()`. `asDelta()` adds `value` to the
synchronization registration of `htmlValue`. Unit tests and ITs cover `EAGER` and `ON_BLUR`.
Team PR, CI green, scale `lite`, head `19823fb`. Quick review at the gate, so no pass ran.
Kept 0 findings, dropped 5, posted nothing.

- The screening printed `gate_default: Full review`. The reviewer picked `Quick review` for a
  38-line fix by a team author with green CI. In review 10, the reviewer picked
  `Full review` for a `lite` team PR of 59 lines. → no change.
- The plan printed `affected_packages: none` and `diff_prod: inline`, so the diff exception
  of `understand.md` applied to a Java fix. The exception names workflow, config and tooling
  changes. `affected_packages` counts only `packages/*`, so in a repo without that directory
  every small PR read the diff before the gate. Here the read was useful, but by accident.
  → the plan prints `prod_source`, the production files under `src_glob`. The exception
  applies when it counts none (`f529a47`, `15aadb6`).
- The orchestrator skipped `gh-context.sh` in Understand. The plan already held the title,
  the body, CI and 0 threads, and no issue was linked. → no change.
- The fix depends on Flow internals outside the diff. The orchestrator read
  `AbstractSinglePropertyField.doSetSynchronizedEvent` from the `flow-server` sources jar in
  `~/.m2`. It confirmed that `setValueChangeMode()` replaces the registration, so the second
  `synchronizeDeltaValue()` call is necessary. The `flow-data` sources jar was not in `~/.m2`,
  so `ValueChangeMode.eventForMode(null)` stayed unread. The unit test
  `asDelta_setValueChangeModeNull_noSynchronization` covered it.
- The local web-components checkout cleared one candidate. `vaadin-rich-text-editor-mixin.js:358`
  debounces `value` by 200ms, so the `EAGER` IT that types 3 keys is not flaky. Line 580
  flushes the debounce only on `focusout`, which fires after `blur`. The `ON_BLUR` IT waits
  for `htmlValue` before it blurs for that reason. The stale value on a fast blur existed
  before the PR, so it went to the chat as a side note. The checkout was not compared with
  the pinned `25.4.0-alpha5`.
- Triage dropped 5 candidates: 2 pre-existing, 2 unverified, and 1 rigor that the codebase
  does not follow. Ten unit tests in other modules already read `ElementListenerMap`
  expressions. The findings file holds all 5 as `dropped`.
- All three post options would post nothing, and `present.md` drops such options. Only
  `No — chat only` stayed, so the orchestrator asked no post question. `present.md` does not
  name this case. → no change.
- Four orchestrator Bash calls failed in zsh. Two failed on `echo ====` again, after the
  review 10 note to use `echo '---'`. Two failed with `no matches found` on an unquoted glob
  (`--include=*Test.java`, `*sources.jar`). A note did not stop the repeat. → no plugin
  change. `bash-guard.py` acts only on the reviewer agents, and a denial costs the same call
  as the zsh error. The fix is in the user environment: run the Bash tool under bash, or
  `setopt NO_NOMATCH NO_EQUALS`.
- Cost: no subagents, about 25 tool calls in the main context.

## 2026-11-09 — Self-review: web-components #13312, PDF viewer print

The branch `feat/pdf-viewer-print` adds `print()`, the print button, `printButtonHidden` and
the `printing` state. Head `d13fa73`, feature, scale `full`, 536 production lines in 17 files.
The run used two rounds of three opus passes, the report and 15 mutants. It found 41 findings:
16 B, 22 C, 3 accepted, no A. Verdict: ready for PR.

- The plan printed `notes: ... (not written ...)` in both rounds. A `context-notes.md` from the
  Nov 6 `feat-pdf-viewer-sidebar` run was still on disk. Line 277 of `review-plan.sh` prints the
  status without checking the file. The notes path is the same for every branch. An
  orchestrator that skips the notes file sends passes the facts of another branch.
  → the plan deletes the notes file and the patches of an earlier context when it writes a
  new one. A smoke check pins it (`392968d`).
- Round 2 on the same head found 19 new findings, 9 of them B. Two were logic defects that
  round 1 missed: `isInside()` walks from a removed element, and `_printing` clears before
  the synchronous `print()`. This confirms the 2026-11-02 dry run. → no change.
- The round 2 change pass read `PdfViewerI18n.java` in `../flow-components` without a lead. It
  found the missing `print` field, the one finding outside this repo. → no change.
- The change pass cleared the open tooltip report of the reviewer from round 1 by reading the
  code. The orchestrator moved the cleared lead into the Settled facts for round 2, and no pass
  raised it again. → no change.
- 8 of 15 mutants survived. The tests pass had already filed 7 of them as coverage gaps:
  4 in round 1 and 3 in round 2. The eighth was an equivalent mutant. No mutant found a gap
  that the passes missed. → no change. The mutants confirmed the test findings.
- The orchestrator wrote a helper in the scratchpad for each mutant. It ran the tests, restored
  the file, checked the clean tree and printed `KILLED` or `SURVIVED`. Each mutant took about
  20 seconds with `--glob="print*"`. → `scripts/mutant.sh` runs a baseline or one mutant,
  restores the file and checks the clean tree. mutation.md calls it (`0c1f68e`, `72c40bc`).
- The repo lint hook reported `no-unused-vars` on 2 mutants that removed the last use of an
  import. The mutants were restored, so this was noise. → no change.
- The report template has no finding ids, but the findings file has them. An author who
  disputes a finding by id at the gate cannot see the id. → the gate, the report lines and
  the follow-ups show the id of the findings file (`ebfe072`).
- Cost: about 525k subagent tokens. Round 1: change 92k with 21 calls, code 84k with 12 calls,
  tests 85k with 9 calls. Round 2: change 93k with 26 calls, code 82k with 13 calls, tests 89k
  with 15 calls. Each round took about 4 minutes.

## 2026-11-09 — PR review 10: flow-components #10597, PDF viewer download API

One production file, `PdfViewer.java`, +59, and 5 new tests in `PdfViewerTest.java`. The PR
adds `download()`, `getFileName()`, `setFileName()` and `setDownloadButtonVisible()`. Team PR,
CI green, scale `lite`. Full review with three passes. Posted 4 threads (1 question,
1 suggestion, 2 nitpicks) at head `e1d19d5`.

- The plan printed `wc_property: fileName -> @vaadin/pdf-viewer@25.4.0-alpha5
  packages/upload/src/vaadin-upload-file-mixin.js:50`. The lookup matched a property of
  another package in the bundle. The real declaration is in web-components #13301, which the
  pinned alpha5 does not contain. The orchestrator corrected it in the Settled facts.
  → the lookup reads only the package of the component (`2bf045f`). Re-run on #10597, the
  line shows `fileName -> not in @vaadin/pdf-viewer@25.4.0-alpha5, declared after it at
  origin/main` (`b1ea863`).
- The plan printed `gate_default: Full review`. The orchestrator recommended `Quick review`
  in the chat but listed `Full review` first without a mark. The reviewer chose
  `Full review`. → no change.
- The passes returned 9 findings, and triage kept 4. The tests pass cited the
  one-test-per-property rule of `CONVENTIONS.md`. That rule landed on main on Nov 6 (#10565),
  and the branch merged main after it. The conventions excerpt carried the rule.
- The tests pass did not read the notes file, because no lead named it. It then filed the
  `EnableFeatureFlagExtension` as unverified noise. A Settled fact already explained it:
  `onAttach` checks the flag, and the download test attaches the viewer. Triage dropped it.
  → the prompt block tells every pass to read the notes file, also with no lead, and to end
  with `notes: <n> settled, <m> leads`. The roll call compares that line with the notes file
  (`f8cd97e`, `1e0472f`).
- The change pass again filed the client error of the pinned alpha before the version bump.
  The PR note and a Settled fact both said so. Triage dropped it, as in review 9.
  This is the second run with the same drop. → the Flow fact pack prints a `wc_method` line
  for each `callJsFunction` call. It marks an API that is newer than the pinned version as
  `declared after it`, with a rule that a client error at the pinned version is not a
  finding. Re-run on #10597, it names `download()`, `fileName` and `downloadButtonHidden`
  (`b1ea863`).
- The change pass rated the queued `download()` on a detached viewer as a B behavior issue.
  `callJsFunction` queues by Flow design, and the queue also lets a call before `add()` work.
  Triage posted it as `question (design)`.
- The code pass anchored its finding at `PdfViewer.java:459`. The Javadoc is at line 174.
  The change pass anchored the same claim at line 173, and triage deduped by claim.
- The orchestrator anchored the design question at line 224. It read the line from
  `sed -n` piped to `cat -n`, which numbers the output from 1. The method is at line 217, and
  the hunk ends at line 223. The dry run of `post-review.sh` did not flag it. The post demoted
  the thread to a file thread. → `post-review.sh` refuses a line outside the hunks of the PR
  diff, also in a dry run. Replayed on #10597, it refuses line 224 and names the hunk
  159-223 (`7522ed1`).
- Two orchestrator Bash calls failed on `echo =====`. In zsh, a word that starts with `=`
  expands to a command path. → no change. Use `echo '---'` as a separator.
- Cost: about 118k subagent tokens (change 48k with 11 calls in 97 seconds, code 33k with
  3 calls, tests 37k with 3 calls). The code and tests passes ran on sonnet.

## 2026-11-06 — PR review 9: flow-components #10594, PDF viewer toolbar actions

One production file, `PdfViewer.java`, +42, and one new unit test file. The PR adds
`getToolbarActions()`, a `HasComponents` container in the `toolbar-actions` slot. Team PR,
CI green, scale `lite`. Full review with three passes. Posted 1 thread (1 suggestion) at
head `7a31391`.

- The orchestrator wrote the Settled facts from two auto-memory notes and one grep. The
  notes named the `Dialog.DialogHeaderFooter` wrapper and the `getChildren()` leak of a
  slotted wrapper. The grep found the class at `Dialog.java:1039`. The code pass cleared its
  lead with that precedent in 4 tool calls. → no change.
- The passes returned 8 findings, and triage kept 1. The change pass found that the sibling
  slot containers carry the component name (`DialogHeader`, `LoginOverlayFooter`). The
  other 7 were C findings or design choices that the Dialog precedent already accepts.
- The tests pass cited `CONVENTIONS.md:260` as `src:`. The file has 163 lines, and the rule
  is at line 111. Line 260 is the line of the rule in the conventions excerpt of the context
  file. Triage had to search for the rule. → the excerpt prints the source line number on
  each quoted line, and the header asks for `src:<doc>:<that number>` (`7c3f9a7`, `e723249`).
- The bot thread 4483966135 was resolved, and later commits fixed the Javadoc. The change
  pass reported a related claim: the pinned alpha5 has no download button, so the Javadoc
  order does not hold yet. The PR note already said so, and triage dropped it. No pass
  repeated the bot claim. → no change.
- Across reviews 8 and 9, the passes returned 11 C findings. Triage posted none of them. In
  review 9, 4 of the 5 findings of the change pass were C. The reviewer wanted them on the
  PR. → the triage filter of pr-review keeps a confirmed C finding that the PR introduced,
  and posts it as a `nitpick`. The drop rule for style nits is gone (`94b40ec`).
- The plan again printed `commands: lint=unknown test=unknown (source: package.json scripts)`
  and `reach: no package source changed`. → see the npm item of review 7.
- Cost: about 128k subagent tokens (change 56k with 14 calls, code 36k with 4 calls, tests
  36k with 3 calls). The code and tests passes ran on sonnet. Each finished in less than
  15 seconds.

## 2026-11-06 — PR review 8: flow-components #10596, PDF viewer zoom API

Three production files, +287, and three test files. The PR adds a `Zoom` value type,
`getZoom()`, `setZoom()`, a read-only `zoomSignal()`, a `ZoomChangeEvent` and TestBench
helpers. Team PR, CI green, scale `full`. Full review with three opus passes. Posted
2 threads (1 blocking issue, 1 suggestion) at head `71f03ec`.

- The plan printed `verdict_hint: take` and `skipped_flags: feature-no-ac (team author)`.
  The fix of review 7 worked, and the gate needed no correction.
- All three passes found the blocking finding independently. On the first update,
  `PolylitMixin` dispatches `zoom-changed` with the default `'page-width'`. Flow
  `MapProperty.getSyncToServerCommand` syncs the value because the server value is `null`.
  The listener then fires a `ZoomChangeEvent` with `fromClient=true`, but the zoom did not
  change. The orchestrator confirmed the chain with 2 source reads, not with a browser run.
- The `page` listener of review 7 has the same flaw. The `page` property is `notify: true`
  with the default `1`. Review 7 did not find it. Its Settled facts covered the
  `@Synchronize` replay, but not the first notify of a default value. → each `wc_property:`
  line prints `notify` and the default value. Settled facts add a note when a property has
  `notify=true`, and `agents/change-reviewer.md` asks the change pass to check the first
  sync. Re-run on #10523, the line shows `page` with `value=1 notify=true` (`4fa6bc8`,
  `6f0a603`).
- The orchestrator again read the web component properties at the pinned version by hand,
  in 2 calls. The facts were the `zoom` declaration, the fallback to `page-width` and the
  toolbar values. → see the property item of review 7.
- The code pass and the change pass reported the same TestBench finding on `getZoom()`.
  The code pass anchored it on line 54, the signature. The change pass anchored it on
  line 55, the `return` statement. Triage matched them by claim. → no change, because
  `pipeline.md` §3 already requires the declaration line.
- The notes file gave both Open leads to the change pass. It cleared both with a source
  reference: the echo of `setZoom` from the client, and the `@Synchronize` replay on
  reattach.
- The tier of the blocking finding was a judgment call again. The component is
  experimental, and a read of the code confirmed the claim, not a run. The orchestrator
  chose A, because it read each source line of the chain. The Javadoc of the PR promises
  that `ZoomChangeEvent` fires when the zoom changes. → see the `severity.md` item of
  review 7.
- The revert check did not run, because the type is `feat`.
- Cost: about 179k subagent tokens (tests 64k with 14 calls, change 60k with 16 calls,
  code 55k with 8 calls).

## 2026-11-05 — PR review 7: flow-components #10523, PDF viewer page API

One production file, `PdfViewer.java`, +110 −3, and two test files. The PR adds a read-only
`page` and `pageCount` API: getters, read-only signals and a `PageChangeEvent`. Team PR, CI
green, scale `lite`. Full review with three passes. Posted 4 threads (1 blocking issue,
1 question, 2 suggestions) and 1 reply in a bot thread, at head `5f25ba2`. The author fixed
the blocking finding in `fb9977d`.

- The hint said `decide` because of `feature-no-ac`, although the plan printed
  `pr_author: vursen (team)`. The orchestrator corrected the hint at step 2:

  > I'm overriding the script's hint. It suggested `decide` because no issue with acceptance criteria is linked. That rule is meant for outside contributors.

  The row in `screening.md` cites the PR template of web-components. That template asks an
  outside contributor for an issue with acceptance criteria first. A team member takes a
  feature from the backlog. `self-filed` had the same fault: a team author who files an
  issue confirms it. → `pr-screen.sh` sets both flags only for a contributor. For a team
  author, it prints them in `skipped_flags:` (`d4a64c3`, `795facf`).
- At the gate, the reviewer asked to check the latest commits first. The head had moved
  from `47b2eb4` to `5f25ba2`: a refactor and its revert. The orchestrator compared the
  trees by hand (`git diff` was empty). → `pr-refresh.sh --context <file>` prints
  `head_moved:`, `tree_changed:`, `ci:`, `new_threads:` and one `action:` line for each
  change. Step 3 runs it before the gate question, and step 5 runs it before triage
  (`bc6653b`, `3c16b94`). On the context of this run, it listed 4 new commits, 6 new threads
  and 3 new replies.
- A `vaadin-review-bot` review arrived after the plan ran, so triage never saw its threads.
  The `post-review.sh` dry run skipped the `pageCount` finding next to a bot thread, and
  its skip line said to reply into that thread. The posted reply repeated the bot claim
  without a check. → step 5 dedups against `new_threads:` too. `pipeline.md` §5.2 says that
  a posted comment repeats the claim of another thread only after triage confirms it. The
  skip line of `post-review.sh` asks to triage the thread first (`4fbae77`, `bc6653b`).
- The bot claim was false. It said that `document-load` reaches the server before
  `page-count-changed`, so a load listener reads the old `getPageCount()`. Flow applies all
  property syncs of a request before it fires events (`ServerRpcHandler.handleInvocations`).
  The author answered in the thread and added an integration test (`8256f3a`). No pass
  reported the claim, which was correct. §5.2 already said to verify an open thread, but
  the thread was not in the skeleton. → a checklist item on event order is not added.
- `post-comment.sh` posted the reply outside the review. The census in the review body says
  1 issue, but the run posted 2 issues. → open: `post-review.sh` accepts `"reply_to": <id>`
  on a finding, posts the reply in the same run and counts it in the census.
- The blocking finding came from the change pass (opus, 15 tool calls, 3.5 minutes).
  `@Synchronize` stores the client `page` in the property map. On reattach,
  `NodeMap.generateChangesFromEmpty` sends it to the new element together with `src`. The
  web component then skips its reset to page 1. The orchestrator confirmed the chain by a
  read of the code. The pass found it without a checklist item, so none is added.
- The orchestrator read the web component properties at the pinned `@NpmPackage` version by
  hand and wrote them as Settled facts. The plan printed `flow_counterpart: none`, a fact
  that is always empty for a Flow PR. → in a Flow repository, `diff-facts.sh` prints a
  `wc_property:` line for each property that an added Java line syncs. It reads the
  declaration at the tag of the pinned `@NpmPackage` version in `../web-components`
  (`4fa6bc8`, `685732c`).
- The tests pass returned 8 findings. Triage kept 1 and merged 1 into the blocking finding.
  Two B findings asked for rigor that the codebase does not use. One was an `Integer`
  against a `Double` client value, which `getProperty(String, int)` accepts. The other was
  a test of `ValueSignal` notification, which is Flow behavior. → open: in
  `agents/test-reviewer.md`, a test of framework behavior or of a framework value
  conversion is C at most.
- The tier of the blocking finding was a judgment call. The component is experimental
  behind a feature flag. A follow-up fix in `setSrc` needs no API change. The tie-breaker
  in `severity.md` does not cover an experimental component. The orchestrator chose A,
  because the Javadoc of the PR promises page 1. → the feature rule of `severity.md` says
  that code that contradicts a promise of the PR Javadoc is A, also on an experimental
  component (`6fd3277`).
- The plan printed `commands: lint=unknown test=unknown (source: package.json scripts)` and
  `reach: no package source changed`. Both lines use the npm model, and flow-components is
  a Maven repo. They cost no call, but they are noise. → with a root `pom.xml`, the plan
  prints the Maven commands. In a Flow repository, `diff-facts.sh` omits the `reach:`,
  `snapshot_packages:` and `flow_counterpart:` lines (`20cd076`, `4fa6bc8`).
- The revert check did not run, because the type is `feat`.
- Cost: about 146k subagent tokens across three passes (change 65k, tests 44k, code 37k).
  The code pass used 3 tool calls.

## 2026-11-04 — PR review 6: web-components #13354, a workflow-only chore

One file, `.github/workflows/code-review.yml`, +33 −14: a `dismiss-stale-approval` job and
the `github.token` fallback removed. Team PR, CI pending. Quick review at the gate, so no
pass ran. Posted 2 threads (1 suggestion, 1 question) at head `337d844`. The author fixed
both within the hour (`5b7465f`, `4213fb0`) and resolved the threads.

- The CI override set `scale: full` and planned three opus passes, the tests pass included,
  for 47 YAML lines with no test file and no testable code. The reviewer picked
  `Quick review`. → the plan drops the tests pass when no test, code or binary file
  changed, and prints `passes_dropped:`. The CI override still raises the scale (`a8213d0`, `7d60103`).
- The facts that decided the review were outside the diff and outside the plan:
  - the `uses:` target at its branch ref (`vaadin/github-actions/code-review@feat/risk-assessment`)
  - its `action.yml` inputs and the `dismiss-stale-approval.mjs` script
  - the repo default token (`actions/permissions/workflow`: `write`, may approve)
  - Dependabot activity on the repo

  Each took a manual `gh api` call. → `workflow-facts.sh` and a `workflow:` block in the plan
  and in Settled facts: added `uses:` refs with their ref kind and an `action.yml` path, jobs
  without `permissions:`, the repo default token, and bot authors in the last 30 days.
  Re-run on `337d844`, it printed both posted findings as facts (`a8213d0`).
- `understand.md` says not to read the diff in step 2. For a workflow PR the diff is the
  explanation, and both leads came from it before the gate. → `understand.md` allows the
  diff when `affected_packages` is none and the diff is inline, and reads each `uses:` action (`5440afd`).
- The action source cleared one suspected finding before the gate: a review still running
  during a push. `post-review.mjs` dismisses its own approval when the head moved. Without
  the external read, it would have been a false `issue`. The CI bot posted that exact
  finding, and a maintainer dismissed it: the action already handles the race.
- One claim stayed unverified: whether the runner uses the input default `github.token`
  when the caller passes an explicit empty secret. It posted as a `question`, as the
  rendering table requires.
- `post-review.sh` prints only the review URL. Step 7 asks for the link of each comment, so
  one more `gh api .../reviews/<id>/comments` call was needed → `post-review.sh` prints the
  URL on each `line:` and `file:` line (`9692b12`).
- Cost: no subagents, about 15 tool calls in the main context.

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
