# Contracts of the review core

This file lists the interfaces that the review skills, the passes and the scripts share.
A change to one of these contracts edits this file in the same commit. `scripts/smoke.sh`
checks that the plan prints only the keys of the list below.

## Plan keys

`scripts/review-plan.sh` prints one `key: value` line per key after `=== PLAN ===`. An
indented line belongs to the key above it. The skills and `references/pipeline.md` quote
these names. Keep each name. A key that the plan prints only in some runs carries a
condition in the comment.

```
mode               self or pr
guard              ok, or refuse: <reason>. A refusal exits 2
note               only when the context script failed
branch             the checked-out branch, or (detached)
head0              HEAD of the working tree at the start
base               the merge base SHA
head               the head SHA under review
base_branch        the base branch and the source of the base
pr                 the PR argument, or none
fork               pr mode: true or false, and the head repository
hint               an instruction for the orchestrator. It can repeat
ci                 the CI digest, or not gathered
existing_comments  the summary of the threads on the PR
screening          pr mode: the screening facts, indented
diff_facts         the diff facts and the fact packs, indented
workflow           a workflow file changed: the workflow facts, indented
type               fix, feature, refactor, chore or undetermined
type_signal        the signal that set the type
type_conflict      none, or a more demanding lower signal
scale              trivial, lite or full
scale_counts       production lines, all lines, files
scale_reason       size, or the risk override
deep               the deep budget of the change pass and its source
deep_candidates    the count of .d.ts files, new exports and new public methods
effort_per_pass    the tool call ceiling of each pass
coverage           self mode: on or off. pr mode: n/a
mutants            the mutant budget of the coverage stage
mutant_pool        mutants above 0: the source lines that a mutant can change
round              the round of this run and the rounds budget
earlier_findings   none, ignored, unreadable, same, delta or rewritten
findings_file      self mode: the path of the findings file
conventions_doc    the conventions doc, or none
passes             the passes with agent, model and lane, indented, or none
agents             the number of passes
passes_dropped     a pass that the diff gives no subject
launch             the launch rule of the fan-out
prod_files         the production lane
test_files         the test lane
binary_files       the binary lane
comment_files      files with a comment in or beside a hunk
commits            the commits of the branch, oldest first, indented
findings           pr mode: the path of the findings file
report_dir         self mode: the report directory
report             self mode: the path of the report
context            the path and size of the context file, or why it was not written
notes              the path of the notes file of the orchestrator
diff_prod          inline, none, or the patch path of the production lane
diff_tests         inline, none, or the patch path of the test lane
commands           the lint and test commands and their source
affected_packages  the packages/* directories that the diff touches
risk_check_manual  a test file changed: the check that the script cannot do
```

## Fact provider

A fact pack is an executable `scripts/facts/<name>.sh`. `scripts/diff-facts.sh` runs it.

- It runs from the repository root with `--base <sha> --head <sha>`.
- The env holds `FACTS_PROD` and `FACTS_TESTS`, one path per line.
- A pack that does not apply to the repository prints nothing.
- Otherwise it prints `<key>: <value>` lines.
- A `rule: <sentence>` line tells the passes how to judge the fact lines above it.
- A pack may print `reach_max: <n>`, the most other packages that import one changed module. The default is 0.

## Findings file

self-review writes the findings file at the `findings_file:` path of the plan, per
`skills/self-review/references/finalize.md`. The plan reads it with `jq`.

- Top-level fields: `branch`, `head`, `base`, `date`, `round`, `verdict`, `findings`.
- A file without `verdict` is the record of a run that did not finish.
- Each finding holds `id`, `round`, `category`, `tier`, `status`, `file`, `line`, `claim`, `fix`, `verified` and `merged`.
- `status` is one of `open`, `accepted`, `fixed`, `partially_fixed`, `fixed_wrongly`, `not_fixed`, `obsolete` and `disputed`.

pr-review writes its findings file at the `findings:` path of the plan, in the format that
`scripts/post-review.sh --help` prints.

## Prompt block

After the plan, `scripts/review-plan.sh` prints `=== PROMPTS ===` and one block per pass:

```
--- <pass> · subagent_type: <plugin>:<agent> · model: <model> ---
Context file: `<context path>` — read it first. Then read `<notes path>` whole if it exists. Its Settled facts bind every pass, also a pass that owns no lead.
End your reply with one line that counts that file: `notes: <n> settled, <m> leads`, or `notes: none` when it does not exist.
Your diff: <lane>.
<the prompt adds of the pass>
Effort ceiling: ~<n> tool calls (scale <scale>) — a ceiling, not a target; your definition names the drop order.

<the delivery clause of references/delivery.md>
--- end ---
```

The orchestrator pastes each block verbatim as the prompt of one Agent call.
