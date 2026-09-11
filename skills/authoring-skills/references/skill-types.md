# Skill type taxonomy — a "which bucket?" checklist

Anthropic catalogued their internal skills and found that they cluster into a
small number of categories. The value of the framework for authoring: *the best
skills fit cleanly into one; the ones that try to do too much straddle several
and confuse the agent.* This repo needs five buckets. Use the list to (a)
sanity-check that your idea is one job, and (b) spot gaps in the skill library.

Each category points at a real skill **in this repository** (in backticks), so
that you can open that skill and copy the shape.

## The five categories

### 1. Code quality & review
Reviews code against a rubric, a checklist, or a skeptical stance. May post
findings. Report-producing, mostly read-only.
- In this repo: **`self-review`** (own branch, pre-PR, three checklist passes),
  **`guided-review`** (interactive PR walkthrough, never posts),
  **`adversarial-review`** (skeptical pass, one summary comment),
  **`pr-review`** (rubric pass, inline comments).
- This is the crowded bucket. Every new skill here **must** carry a boundary
  clause against the existing four.

### 2. Verification & testing
Describes how to prove that code works: coverage checks, test-writing
procedures, external drivers. *Anthropic: verification skills had the most
measurable impact on output quality — worth the effort to make excellent.*
- In this repo: **`mutation-coverage`** (mutation testing + closing the gaps
  with tests).

### 3. Code transformation
Changes production source and keeps the behavior. Writes code, not a report. This
is the only bucket that edits the files that the other buckets read.
- In this repo: **`refactor-component`** (structural refactor of component
  sources, from the mixin chain outward), **`comment-cleanup`** (deletes and
  shortens the comments that a diff added).
- Boundary against bucket 2: a transformation skill rewrites production code. A
  verification skill adds tests. `mutation-coverage` writes tests, so it belongs
  to bucket 2.
- Boundary against bucket 1: a transformation skill edits. A review skill reports
  and leaves the decision to you.
- Every new skill here **must** carry a boundary clause against the built-in
  `simplify`, which cleans up an uncommitted diff.
- Candidates: a codemod skill for a repeated API migration, a deprecation skill.

### 4. Meta / authoring
Skills about the skill system itself.
- In this repo: **`authoring-skills`** (this skill).

### 5. Development workflow
Automates a repetitive git/GitHub workflow end to end. Examples: watch CI,
shepherd a PR, keep commit hygiene. May be long-running or post externally.
- In this repo: none yet. Candidates: a `babysit-pr` (watch the checks of a PR,
  retry flaky jobs, report), a commit-message skill.

## Decision aid (Step 0)

Before you write anything, answer these questions in order:

1. **Which single category above does this fit?**
   - Fits exactly one → good, proceed.
   - Fits two or more → **split into two skills.** A skill that straddles
     categories confuses the trigger and the body. For example, split
     "review *and* fix" into a report-only review skill and an apply skill that
     reads its report. That is the exact split between `self-review` and
     `mutation-coverage`. A skill that reports, a skill that proves and a skill
     that changes the source are three skills, not one.
   - Fits none → it may not be a skill at all. Re-check Step 0.2/0.3 below.
2. **Does it push the model off its defaults?** If it only restates what the
   model already does well, **stop and write nothing**. See the SKILL.md
   anti-pattern "stating the obvious".
3. **Will you reuse it?** One-off → task note. Reused → skill.

> Tip from the Anthropic post: *most of our best skills began as a few lines and
> a single gotcha.* Pick the category. Write the smallest useful version. Grow
> it as the agent hits new edge cases.
