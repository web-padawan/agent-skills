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
stages             the stages of the run, indented, or none
earlier_findings   none, ignored, unreadable, same, delta or rewritten
findings_file      self mode: the path of the findings file
conventions_doc    the conventions doc, or none
owner_rules        the rules.md of the owner directory, or none
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
notes              the path of the notes file of the orchestrator, deleted by each plan that writes a context, required before fan-out
diff_prod          inline, none, or the patch path of the production lane
diff_tests         inline, none, or the patch path of the test lane
commands           the lint and test commands and their source
prod_source        the production files under src_glob, as <n> of <m>, or unknown
affected_packages  the packages/* directories that the diff touches
risk_check_manual  a test file changed: the check that the script cannot do
```

## Stage

A stage is a step of a skill outside the fan-out, for example a further round or a
coverage check. A stage adds one entry to the registry and the profiles of
`scripts/lib/policy.sh`, and it adds files. It changes no core line.

- **Registry**: `stage_info <name>` prints the slot, the ask flag and the reference file of the stage.
- **Profile**: `plan_policy` adds `<name>=<budget>` to `STAGE_LIST` for each stage of the mode and the change type.
- **Plan**: the plan prints `stages: none`, or `stages:` and one indented line per stage.
- **Stage script**: the plan runs `scripts/stages/<name>.sh` when it exists, and indents its output under the line of the stage.
- **Flags**: `--off <stage>` removes a stage from the run. `--budget <stage>=<n>` sets its budget. An unknown stage or a bad budget exits 1.
- **Slots**: self-review has the slots `after-triage` and `after-gate`. At each slot, the skill runs every listed stage of that slot, per its reference file.
- **Gate**: the gate asks one question for each listed stage with `ask yes`. The reference file of the stage holds the question.
- **Carve-out**: the reference file of a stage can permit an edit of a tracked file. `SKILL.md` names each such stage in its rules.
- **pr-review**: it has no slot. A stage for pr mode needs a slot in that `SKILL.md` first.

Stage keys. A stage script prints them under the line of its stage, indented by four spaces:

```
round              rounds: the round of this run and the budget, as <k> of <n>
mutants            coverage: the mutant budget
mutant_pool        coverage, budget above 0: the source lines that a mutant can change
error              a stage script that failed
```

The line of a stage:

```
  <name>: slot <slot>, budget <n>, ask <yes|no>, ref <reference file>
```

A stage script runs from the repository root:

- It takes `--base <sha>`, `--head <sha>` and `--budget <n>`.
- The env holds `FACTS_PROD` and `FACTS_TESTS`, one path per line, and `STAGE_FINDINGS`, the path of the findings file of self mode. It is empty when the plan did not read that file: with `--fresh`, or when the file is unreadable.
- It prints `<key>: <value>` lines. A failure prints `error: stages/<name>.sh failed` and the last line of its output.

## Fact provider

A fact pack is an executable `scripts/facts/<name>.sh`, or `<owner dir>/facts/<name>.sh`.
`scripts/diff-facts.sh` runs it.

- It runs from the repository root with `--base <sha> --head <sha>`.
- The env holds `FACTS_PROD` and `FACTS_TESTS`, one path per line.
- The env holds `FACTS_MODE` (`self` or `pr`), `FACTS_PR` (the PR argument, or empty), `FACTS_OFFLINE` (`1` with `--no-context`, else empty) and `FACTS_OWNER`.
- A pack that does not apply to the repository prints nothing.
- Otherwise it prints `<key>: <value>` lines.
- A `rule: <sentence>` line tells the passes how to judge the fact lines above it.
- A pack may print `reach_max: <n>`, the most other packages that import one changed module. The default is 0.
- `diff-facts.sh` prints `fact_packs: <name>, ...` for the packs that printed a line, or `fact_packs: none`. A pack of an owner directory is named `<owner>/<name>`.

## Owner directory

`scripts/lib/owner.sh` finds the owner directory of a repository.

- The owner is the owner of the `upstream` remote, else of `origin`, in lowercase. `pr-screen.sh` takes it from the PR.
- The directory is `<config dir>/<owner>/`, else `<plugin root>/owners/<owner>/`.
- The config dir is `REVIEW_SKILLS_CONFIG_DIR`, else `${XDG_CONFIG_HOME:-~/.config}/<plugin name>`.
- It holds `facts/*.sh`, `screening.json` and `rules.md`. Each one is optional.
- The packs of an owner run only in the repositories of that owner.

## Findings file

self-review writes the findings file at the `findings_file:` path of the plan, per
`skills/self-review/references/finalize.md`. The plan reads it with `jq`.

- Top-level fields: `schema`, `branch`, `head`, `base`, `date`, `round`, `verdict`, `findings`.
- `schema` is 1. The plan reads a file without `schema` as schema 1. It prints `earlier_findings: unreadable (schema <n>)` for a higher schema.
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
`scripts/hooks/notes-guard.py` reads the `Context file:` line. It denies the Agent call while
the context file or the notes file does not exist. Keep the wording of that line and the
pattern of the hook in step. `scripts/smoke.sh` checks the hook against a printed prompt.
