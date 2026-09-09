# Frontmatter field reference

Every `SKILL.md` opens with a YAML frontmatter block delimited by `---`. This
plugin uses the skill fields of Claude Code. Two fields, `name` and
`description`, are mandatory. A small set of fields is optional. No CI enforces
this reference. The checklist at the bottom is the gate.

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
- **What:** the identifier of the skill. `/agent-skills:<name>` invokes it.
- **Convention:** **kebab-case**, and it **matches the folder name of the skill**
  (`pr-review/` → `name: pr-review`).
- No spaces, no uppercase, no underscores.

### `description` (required)
- **What:** the single most important field. The model scans the description of
  every skill to decide whether to trigger that skill. It is a *description of
  when to trigger*, not a summary.
- **Convention:** third-person present. Lead with trigger verbs or phrases.
  Enumerate situations. Add a boundary clause that names the sibling skills that
  the model must not confuse with this skill. Longer is fine when the skill
  legitimately covers many phrasings.
- See **`descriptions.md` (next to this file)** for patterns, worked before/after
  examples, and the litmus test.

## Optional fields

### `argument-hint`
- **What:** the usage hint shown next to the slash command.
- **Convention:** quote it. Use `<angle>` for required parts, `[square]` for
  optional parts, and `|` for alternatives. Example from `mutation-coverage`:
  `"<file|--package <pkg>|--diff> [--stryker] [--test '<command>']"`.
  Add it whenever the skill takes a positional input or flags.

### `disable-model-invocation`
- **What:** `true` removes the skill from the auto-trigger pool of the model.
  The skill then runs only when the user types the slash command.
- **Convention in this repo:** set `true` on any skill that is **expensive** or
  that can **post outside the machine**. Expensive skills include multi-agent
  orchestration (`self-review`) and long test runs (`mutation-coverage`). PR
  comments (`pr-review`, `adversarial-review`) post outside the machine.
  Read-only, bounded skills (`guided-review`, `authoring-skills`) stay
  auto-triggerable, because their descriptions do the routing. The middle case
  is an auto-triggerable skill with a bounded common path and an unbounded wide
  path. Such a skill gets an in-body confirmation gate before the wide path
  spends its budget.

### `allowed-tools`
- **What:** restricts which tools the skill may call, for example
  `Read, Grep, Glob, Bash(gh pr view:*), Bash(git diff:*)`.
- **Convention:** use it when tool scope can enforce the contract of the skill.
  A read-only review skill that must never edit gains a real guarantee from a
  list without `Edit`/`Write`. Omit it for skills that legitimately need broad
  access. Note *why* a surprising entry is there. See `self-review`, whose
  `Edit` exists for one documented carve-out.

## Not used in this repo

`version`, `license`, `category`, `compatibility`, `metadata.*` are fields from
other skill ecosystems with CI around them. There is no CI here, and the plugin
is pinned per commit, so these fields are noise. Do not add them.

## Linting checklist

- [ ] `name` is kebab-case and equals the folder name.
- [ ] `description` is present and **trigger-shaped** (passes the litmus test
      in `descriptions.md`), third-person present, and names its sibling
      boundaries.
- [ ] YAML is valid (`---` on its own line opens and closes the block, no tabs).
- [ ] `disable-model-invocation: true` if the skill is expensive or can post
      externally.
- [ ] `argument-hint` present if the skill takes arguments.
- [ ] No secrets or machine-specific absolute paths in frontmatter.
- [ ] The body obeys `.claude/rules/writing-style.md`. The `description` field is
      exempt. It follows the trigger conventions in `descriptions.md`.
