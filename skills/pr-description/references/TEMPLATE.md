# Output template

The skeleton below is the whole output. Put nothing above `## Description` and nothing
below the last section. That means no checklist, no footer, no attribution.

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

**Links first, one per line, no bullet.** Use `Fixes <url>` only when the merge closes the
issue. Otherwise use `Part of`, `Extracted from #NNNN`, `Depends on <url>`, or
`Related to`. If there is nothing to link, omit the block entirely. Never leave the
`Fixes # (issue)` line of the template.

**Then the bullets.** This is the body of the description. See
[STYLE.md](STYLE.md) for voice.

**Prose between the links and the bullets is optional**. Cap it at one short paragraph.
Add it only when the bullets cannot carry the reason. These are the three reasons:

- a root cause that is not obvious
- a rejected alternative that a reviewer would otherwise propose
- a constraint that shaped the approach

A bug fix with a subtle cause usually earns one paragraph. A feature almost
never does.

### `## Type of change`

One plain bullet, one of the five values. Not a checkbox. In practice, the merged PRs do
not use the `- [ ]` boxes of the template.

### `## How to test`

Numbered steps that a reviewer can follow with no need to read the diff. Every run ends in
something observable. Name a page that exists in the repo.

When the steps need a device or a setting, add a preamble line, for example
`On a touch device, or with touch emulation:`.

**Omit the whole section** when a reviewer cannot exercise the change by hand. This applies
to dependency bumps, type-definition-only changes, test refactors, and internal changes
with no user-visible effect. A missing section is better than "run the tests".

### `## Before / After`

Only for changes with a visual or recorded result: styles, layout, animation, focus rings,
anything where a screenshot or screencast is the clearest evidence.

Scaffold the table with `<!-- paste screenshot -->` in each cell. Tell the user in chat
that they must attach the images before they publish the PR. An agent cannot upload them.
For a screencast, drop the table and leave a single `Before:` / `After:` line each. GitHub
renders video attachments as bare URLs.

Omit the section for anything non-visual.

## Optional extra sections

Only when the change genuinely needs them, always after `How to test`:

- **A behavior table**, `| Case | Before | After |`. Use it when the change alters several
  distinct cases and a list would not make the pattern clear.
- **`> [!NOTE]`**, a single callout. Use it for a side effect that matters to a reviewer
  but is not the point of the PR.

Do not add a section that only restates the bullets.
