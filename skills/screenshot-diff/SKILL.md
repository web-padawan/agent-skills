---
name: screenshot-diff
description: Classify a visual test screenshot change as sub-pixel rendering, transition or animation flakiness, browser update rasterization noise, or a real content change. Use when a visual baseline changed or is about to change (a Playwright or Chromium bump, a component or theme change), when `yarn test:lumo` / `test:aura` / `test:base` left `failed/` screenshots, or when asked to analyze, triage or rank screenshot diffs, compare a PNG with its previous git version, or decide whether to update baselines. Takes a PNG path, a screenshots directory, or nothing for every failed screenshot in the repo. Reports and never updates a baseline. Not for a DOM snapshot diff, which is a text diff.
argument-hint: "[<png> | <dir> | blank for every failed screenshot]"
allowed-tools: Read, Grep, Glob, Bash(git:*), Bash(node:*), Bash(*/scripts/visual-diffstat.cjs:*)
---

# Screenshot Diff

This skill classifies visual test screenshot diffs. A script measures the pixels. You read
the numbers, the related source, and at most one contact sheet. Then you name the class of
each change and the next action. The skill never updates a baseline and never edits a file.

The script is `${CLAUDE_PLUGIN_ROOT}/scripts/visual-diffstat.cjs`. Run it with `node` from
inside the repository. `--help` prints every option.

## Gotchas

- **Do not read the PNGs one by one.** One `Read` of a PNG costs more than the whole table.
  Rank first with the table. Look only at the rows that the numbers cannot settle, through one
  `--sheet`.
- **`runner` is the number that decides the test.** The test runner counts pixels with the
  pixelmatch threshold 0.2 and fails above 0.05 percent. `diff px` counts every changed byte,
  so it is larger. A row with a low `runner` and a high `diff px` is rendering noise.
- **A `wip-failed` directory pairs with `wip-baseline`.** The script maps `<x>failed` to
  `<x>baseline` and falls back to `baseline`. Name the directory when the default walk pairs
  the wrong files.
- **A first baseline has nothing to compare.** The script says so and exits 0. Report it and
  stop.

## Step 1: Measure

Pick the call from the input:

| Input | Call |
| --- | --- |
| nothing | `node <script>` walks every `failed/` and `wip-failed/` directory under `packages/` |
| a directory | `node <script> <dir>` walks that directory |
| a PNG in a failed directory | `node <script> <png>` pairs it with the baseline |
| a tracked PNG | `node <script> --git <png>` pairs it with its previous git version |
| two files | `node <script> --before <a.png> --after <b.png>` |

Several pairs print one table row each, sorted by `pct`. One pair prints a metrics block with
the same fields plus `DELTA_HIST_NONZERO` and seven `SAMPLE` points. The `hint` column holds
the mechanical part of the classification below. `geometry` and `content` need no further
evidence. `subpixel` and `noise?` need the sample points. `region` and `ambiguous` need
Step 2.

For a long table, pass `--top 20`. Pass `--tsv` when you write the numbers into a report.

## Step 2: Read the source for the unsettled rows

Decode the label `<component>/<theme>/<test>` and read, when the file exists:

- `packages/<component>/src/`: grep `transition:`, `animation:` and `@keyframes`.
- `packages/<component>/test/visual/<theme>/<component>.test.js`: the state that the test
  captures, for example `opened`, `error`, RTL or dark.
- the theme CSS: `packages/vaadin-lumo-styles/src/components/<component>.css` for Lumo, or
  `packages/aura/src/components/<component>.css` for Aura.
- for an overlay component, the parent surface package too (`overlay`, `dialog`, `popover`).

A transition counts only when its element overlaps the `bbox` of the row.

When the numbers and the source leave a row open, render one sheet for the open rows:
`node <script> <dir> --top 12 --scale 0.5 --sheet <scratchpad>/sheet.png`. Then `Read` that
one file. Each row shows `before | after | diff` under its label.

## Step 3: Classify

Walk the rows from the top. Take the first verdict that matches.

| # | Verdict | Conditions |
| --- | --- | --- |
| 1 | Content change, geometry | the sizes differ (`geometry`) |
| 2 | Content change, color or structure | `maxΔ` above 32, or more than 50 pixels with Δ above 16 (`content`) |
| 3 | Transition or animation flakiness | `bbox%` under 25, `maxΔ` at most 32, and a `transition` or `animation` on an element inside the box |
| 4 | Browser update rasterization noise | `maxΔ` at most 4, `pct` above 5, the solid sample points identical, the changed pixels in translucent areas such as shadows or the page background |
| 5 | Sub-pixel rendering | `maxΔ` at most 8, `pct` at most 5, the changed pixels spread along glyph and curve edges |
| 6 | Ambiguous | none of the above. Report the two nearest classes with the data for each |

A solid sample point is one that is byte-identical before and after and is not a near-white
or near-black gradient. For verdict 3, name the file, the line and the property.

## Step 4: Report

For one screenshot, print this. The format is fixed.

```markdown
## Analysis of `<path>`

**Bottom line:** <one sentence: the class and the single strongest data point behind it>.

### What the pixels say

| Metric | Value |
|---|---|
| Image size | <W × H> |
| Differing pixels | <N> / <total> (<pct>%) |
| Runner count (threshold 0.2) | <N> (<pct>%, fails above 0.05%) |
| Max per-channel delta | <D> of 255 (R=<r> G=<g> B=<b>) |
| Pixels with delta > 16 | <N> |
| Diff bounding box | <W' × H' at (x,y)> (<bbox%> of canvas) |
| Sample points | <before → after per point, or "all identical"> |

### Why it is, or is not, each class

- **Sub-pixel rendering**: <evidence>
- **Browser update rasterization**: <evidence>
- **Transition / animation flakiness**: <evidence, with file:line when found, else "no transition in the box">
- **Content change**: <evidence>

### Recommendation

<update the baseline as it is / investigate <element> / re-run the test / check the sibling screenshots>
```

For a table, print one line per row: label, verdict, one data point, action. Group the rows by
verdict. Lead with the content changes, because those need a human decision. Close with the
count per verdict and the rows that you looked at on the sheet.

## Rules

- Never run `yarn update:*` and never copy a `failed` PNG over a baseline. The user decides.
- Name the data point behind every verdict. A verdict without a number is a guess.
- Report a row that the script could not pair (`no baseline`) as its own line. Do not drop it.
- Delete the sheet after the run when it lives outside the scratchpad.
