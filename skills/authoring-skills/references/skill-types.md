# Skill type taxonomy — a "which bucket?" checklist

Anthropic catalogued their internal skills and found they cluster into a small
number of categories. The framework's value for authoring: *the best skills fit
cleanly into one; the ones that try to do too much straddle several and confuse
the agent.* This repo needs four buckets. Use the list to (a) sanity-check that
your idea is one job, and (b) spot gaps in the skill library.

Each category points at a real skill **in this repository** (in backticks) so
you can open it and copy the shape.

## The four categories

### 1. Code quality & review
Reviews code against a rubric, a set of lenses, or a skeptical stance; may post
findings. Report-producing, mostly read-only.
- In this repo: **`self-review`** (own branch, pre-PR, type-profiled passes),
  **`arch-review`** (one change through three lenses), **`guided-review`**
  (interactive PR walkthrough, never posts), **`adversarial-review`** (skeptical
  pass, one summary comment), **`pr-review`** (rubric pass, inline comments).
- The crowded bucket — every new skill here **must** carry a boundary clause
  against the existing five.

### 2. Verification & testing
Describes how to prove code works: coverage checks, test-writing procedures,
external drivers. *Anthropic: verification skills had the most measurable
impact on output quality — worth the effort to make excellent.*
- In this repo: **`mutation-coverage`** (mutation testing + closing the gaps
  with tests).

### 3. Meta / authoring
Skills about the skill system itself.
- In this repo: **`authoring-skills`** (this skill).

### 4. Development workflow
Automates a repetitive git/GitHub workflow end to end: watching CI, shepherding
a PR, commit hygiene. May be long-running or post externally.
- In this repo: none yet. Candidates: a `babysit-pr` (watch a PR's checks,
  retry flaky jobs, report), a commit-message skill.

## Decision aid (Step 0)

Before writing anything, answer in order:

1. **Which single category above does this fit?**
   - Fits exactly one → good, proceed.
   - Fits two or more → **split into two skills.** A skill that straddles
     categories confuses the trigger and the body. (e.g. "review *and* fix" →
     a report-only review skill + an apply skill that reads its report — the
     exact split between `self-review` and `mutation-coverage`.)
   - Fits none → it may not be a skill at all; re-check Step 0.2/0.3 below.
2. **Does it push the model off its defaults?** If it only restates what the
   model already does well, **stop — write nothing** (see SKILL.md anti-pattern
   "stating the obvious").
3. **Will it be reused?** One-off → task note. Reused → skill.

> Tip from Anthropic's post: *most of our best skills began as a few lines and
> a single gotcha.* Pick the category, write the smallest useful version, and
> grow it as the agent hits new edge cases.
