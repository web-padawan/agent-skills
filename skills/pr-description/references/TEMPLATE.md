# Output Template

The skeleton below is the whole output. Nothing above `## Description`, nothing below the
last section — no checklist, no footer, no attribution.

```markdown
## Description

Fixes https://github.com/vaadin/web-components/issues/951

- <What changed, one behavior per bullet>
- <…>
  - <Sub-bullet: a detail or the reason, only when the parent bullet needs it>

## Type of change

- <Feature | Bugfix | Refactor | Documentation | Internal change>

## How to test

1. <Open a real page: `dev/split-layout.html`, or the IT view>
2. <Do the thing>
3. <What you should see>

## Before / After

| Before | After |
| --- | --- |
| <!-- paste screenshot --> | <!-- paste screenshot --> |
```

## Per-section rules

### `## Description`

**Links first, one per line, no bullet.** `Fixes <url>` only when merging closes the
issue; otherwise `Part of`, `Extracted from #NNNN`, `Depends on <url>`, `Related to`.
Omit the block entirely when there is nothing to link — never leave the template's
`Fixes # (issue)`.

**Then the bullets.** This is the body of the description. See
[STYLE.md](STYLE.md) for voice.

**Prose between the links and the bullets is optional** and capped at one short paragraph.
Add it only when the bullets cannot carry the *why*: a non-obvious root cause, a rejected
alternative a reviewer would otherwise propose, a constraint that shaped the approach.
A bug fix whose cause is subtle usually earns one; a feature almost never does.

### `## Type of change`

One plain bullet, one of the five values. Not a checkbox — the template's `- [ ]` boxes
are not used in practice.

### `## How to test`

Numbered steps a reviewer can follow without reading the diff. Every run ends in something
observable. Name a page that exists in the repo.

Add a preamble line when the steps need a device or a setting, e.g.
`On a touch device, or with touch emulation:`.

**Omit the whole section** when the change cannot be exercised by hand — dependency bumps,
type-definition-only changes, test refactors, internal changes with no user-visible effect.
A missing section is better than "run the tests".

### `## Before / After`

Only for changes with a visual or recorded result: styles, layout, animation, focus rings,
anything where a screenshot or screencast is the clearest evidence.

Scaffold the table with `<!-- paste screenshot -->` in each cell and tell the user in chat
that the images must be attached before the PR is published — an agent cannot upload them.
For a screencast, drop the table and leave a single `Before:` / `After:` line each, since
GitHub renders video attachments as bare URLs.

Omit the section for anything non-visual.

## Optional extra sections

Only when the change genuinely needs them, always after `How to test`:

- **A behavior table** — `| Case | Before | After |` when the change alters several
  distinct cases and a list would not make the pattern clear.
- **`> [!NOTE]`** — a single callout for a side effect a reviewer should know about but
  that is not the point of the PR.

Do not add a section that only restates the bullets.
