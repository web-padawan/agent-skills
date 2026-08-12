# Frontmatter field reference

Every `SKILL.md` opens with a YAML frontmatter block delimited by `---`. This
plugin uses Claude Code's skill fields: **two required** — `name`,
`description` — and a small set of optional ones. Nothing here is CI-enforced;
the checklist at the bottom is the gate.

```yaml
---
name: my-skill
description: <trigger-shaped sentence — see references/descriptions.md>
argument-hint: "<thing the skill takes>"
disable-model-invocation: true
allowed-tools: Read, Grep, Glob, Bash(git:*), Bash(gh:*)
---
```

## Required fields

### `name` (required)
- **What:** the skill's identifier; what `/agent-skills:<name>` invokes.
- **Convention:** **kebab-case**, and it **matches the skill's folder name**
  (`arch-review/` → `name: arch-review`).
- No spaces, no uppercase, no underscores.

### `description` (required)
- **What:** the single most important field — the model scans every skill's
  description to decide whether to trigger it. It is a *description of when to
  trigger*, not a summary.
- **Convention:** third-person present; lead with trigger verbs/phrases;
  enumerate situations; add a boundary clause naming the sibling skills it must
  not be confused with. Longer is fine when the skill legitimately covers many
  phrasings.
- See **`descriptions.md` (next to this file)** for patterns, worked before/after
  examples, and the litmus test.

## Optional fields

### `argument-hint`
- **What:** the usage hint shown next to the slash command.
- **Convention:** quote it, use `<angle>` for required and `[square]` for
  optional parts, `|` for alternatives. Example from `mutation-coverage`:
  `"<file|--package <pkg>|--diff> [--stryker] [--test '<command>']"`.
  Add it whenever the skill takes a positional input or flags.

### `disable-model-invocation`
- **What:** `true` removes the skill from the model's auto-trigger pool — it
  only runs when the user types the slash command.
- **Convention in this repo:** set `true` on any skill that is **expensive**
  (multi-agent orchestration: `self-review`, long test runs:
  `mutation-coverage`) or that can **post outside the machine** (PR comments:
  `pr-review`, `adversarial-review`). Read-only, bounded skills
  (`guided-review`, `authoring-skills`) stay auto-triggerable — their
  descriptions do the routing. `arch-review` is the documented middle case:
  auto-triggerable because its common auto path (one change, three agents) is
  bounded, with an in-body confirmation gate before a multi-change run spends
  its full agent budget.

### `allowed-tools`
- **What:** restricts which tools the skill may call, e.g.
  `Read, Grep, Glob, Bash(gh pr view:*), Bash(git diff:*)`.
- **Convention:** use it when the skill's contract is enforceable by tool
  scope — a read-only review skill that must never edit gains a real guarantee
  from a list without `Edit`/`Write`. Omit it for skills that legitimately
  need broad access; note *why* a surprising entry is there (see `self-review`,
  whose `Edit` exists for one documented carve-out).

## Not used in this repo

`version`, `license`, `category`, `compatibility`, `metadata.*` — fields from
other skill ecosystems with CI around them. There is no CI here and the plugin
is pinned per commit, so they are noise; do not add them.

## Linting checklist

- [ ] `name` is kebab-case and equals the folder name.
- [ ] `description` is present and **trigger-shaped** (passes the litmus test
      in `descriptions.md`), third-person present, and names its sibling
      boundaries.
- [ ] YAML is valid (the block is fenced by `---` on its own lines; no tabs).
- [ ] `disable-model-invocation: true` if the skill is expensive or can post
      externally.
- [ ] `argument-hint` present if the skill takes arguments.
- [ ] No secrets or machine-specific absolute paths in frontmatter.
