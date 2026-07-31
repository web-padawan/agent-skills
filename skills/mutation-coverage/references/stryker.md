# Stryker engine — setup, run, cleanup

Stryker runs the real test suite once per mutant via its `command` runner, so
the full Web Test Runner environment applies (sendKeys/sendMouse, esbuild, all
plugins). Nothing has to be installed or committed in the target repo: Stryker
itself runs through `npx`, and the config files are materialized as untracked
files. Verified against `@stryker-mutator/core@9` on vaadin/web-components.

## When the repo already has Stryker committed

If `stryker.conf.js` exists in the repo root (e.g. the `proto/stryker-mutation`
branch of web-components), skip materialization entirely and use the repo's own
setup: `STRYKER_GROUP=<pkg> yarn test:mutation`, diff mode via
`yarn test:mutation:diff`. Everything below is for repos without it.

## Materialize (once per repo checkout)

1. Copy the three templates from this skill's `assets/stryker/` into the repo
   root, keeping their names:
   - `stryker-skill.conf.mjs` — the Stryker config (command runner, in-place,
     concurrency 1, incremental, HTML report). Parametrized by `STRYKER_GROUP`.
   - `wtr-stryker-skill.config.mjs` — extends the repo's
     `./web-test-runner.config.js` and forwards the active mutant id into the
     browser page.
   - `stryker-skill-ignore-plugin.mjs` — ignores mutants inside
     `static get styles()` / `static get lumoInjector()` (covered by visual
     tests, not unit tests). Import-free on purpose: it exports the exact
     object `declareClassPlugin()` would build, so it loads without
     `@stryker-mutator/api` in the repo's node_modules.
2. Register the untracked names in `.git/info/exclude` (NEVER `.gitignore` —
   that would be a tracked-file edit). Append any that are missing:
   ```
   stryker-skill.conf.mjs
   wtr-stryker-skill.config.mjs
   stryker-skill-ignore-plugin.mjs
   .stryker-tmp/
   reports/mutation/
   stryker.log
   ```
3. In a repo that is not vaadin/web-components, adjust the parameter block at
   the top of `stryker-skill.conf.mjs` (test command, mutate globs) before
   running.

## Run

Always pass the config path positionally; `--mutate` must come last
(command-line-args consumes all trailing values).

```bash
# One file
STRYKER_GROUP=<pkg> npx --yes --package @stryker-mutator/core@9 stryker run \
  stryker-skill.conf.mjs --mutate 'packages/<pkg>/src/<file>.js'

# Line ranges (what diff mode generates)
... --mutate 'packages/<pkg>/src/<file>.js:83-88'

# Whole package (background job; estimate first)
STRYKER_GROUP=<pkg> npx --yes --package @stryker-mutator/core@9 stryker run stryker-skill.conf.mjs

# PR diff, one Stryker run per touched package
node <skill>/scripts/stryker-diff.mjs [--base origin/main] [--dry-run]
```

- The HTML report lands at `reports/mutation/<group>.html`; machine-readable
  statuses (including `statusReason` for ignored mutants) in
  `reports/mutation/<group>-incremental.json`.
- `incremental: true` makes reruns near-free: unchanged mutants are not
  re-tested. Delete the incremental JSON to force a full run.
- First `npx` call downloads Stryker into the npm cache (~30 s once, then
  instant).

## Estimate before running

Cost ≈ `baseline_suite_time × mutant_count` (+ one baseline dry run). Get the
mutant count from the `Instrumented N source file(s) with M mutant(s)` line —
it appears within seconds, before any mutant runs. If the projected time is
over ~30 minutes, stop and narrow the scope (fewer files, line ranges, diff
mode) or run it as an explicit background job — never silently start a
multi-hour run. Measured on web-components: `yarn test --group accordion`
baseline ~3 s, ~2.5–3 s per mutant.

## Cleanup and safety

- `inPlace: true` restores sources on normal exit and on Ctrl-C, but a SIGKILL
  can leave a mutant applied. Before declaring any run done, require
  `git status --porcelain -- packages/*/src` (or the repo's source root) to be
  empty. Recovery: `git checkout -- <path>`, or copy from the
  `.stryker-tmp/backup-*` directory Stryker printed at startup.
- The materialized files, `reports/mutation/` and `.stryker-tmp/` are excluded
  via `.git/info/exclude`, so `git status` stays clean; leave them in place for
  reruns (the incremental cache lives there) unless the user asks to remove
  every trace.
- Nothing touches `package.json`, `yarn.lock` or `node_modules`.

## Fallback if npx cannot be used

(Offline, registry blocked, or npx resolution broken.) Install temporarily:
`yarn add -D @stryker-mutator/core@9`, run via `node_modules/.bin/stryker run
stryker-skill.conf.mjs …`, then restore with
`git checkout -- package.json yarn.lock`. The extra node_modules content is
harmless; the next `yarn install` reconciles it. The restore MUST run on every
exit path — re-check `git status --porcelain package.json yarn.lock` in the
done condition.
