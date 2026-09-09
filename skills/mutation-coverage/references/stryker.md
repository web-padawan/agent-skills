# Stryker engine — setup, run, cleanup

Stryker runs the real test suite once per mutant through its `command` runner. So
the full Web Test Runner environment applies (sendKeys/sendMouse, esbuild, all
plugins). You do not have to install or commit anything in the target repo.
Stryker itself runs through `npx`, and you materialize the config files as
untracked files. Verification ran against `@stryker-mutator/core@9` on
vaadin/web-components.

## When the repo already has Stryker committed

If `stryker.conf.js` exists in the repo root, skip materialization entirely. For
example, the `proto/stryker-mutation` branch of web-components has one. Use the
setup of the repo instead: `STRYKER_GROUP=<pkg> yarn test:mutation`, and
`yarn test:mutation:diff` for diff mode. Everything below is for repos without a
committed config.

## Materialize (once per repo checkout)

1. Copy the three templates from `assets/stryker/` in this skill into the repo
   root. Keep their names:
   - `stryker-skill.conf.mjs` is the Stryker config (command runner, in-place,
     concurrency 1, incremental, HTML report). `STRYKER_GROUP` parametrizes it.
   - `wtr-stryker-skill.config.mjs` extends the repo file
     `./web-test-runner.config.js`. It forwards the active mutant id into the
     browser page.
   - `stryker-skill-ignore-plugin.mjs` ignores mutants inside
     `static get styles()` / `static get lumoInjector()`. Visual tests cover
     those, not unit tests. The plugin is import-free on purpose. It exports the
     exact object that `declareClassPlugin()` would build, so it loads without
     `@stryker-mutator/api` in the repo node_modules.
2. Register the untracked names in `.git/info/exclude`. NEVER use `.gitignore`,
   because that would be a tracked-file edit. Append each name that is not there
   yet:
   ```
   stryker-skill.conf.mjs
   wtr-stryker-skill.config.mjs
   stryker-skill-ignore-plugin.mjs
   .stryker-tmp/
   reports/mutation/
   stryker.log
   ```
3. In a repo that is not vaadin/web-components, adjust the parameter block at
   the top of `stryker-skill.conf.mjs` before you run Stryker. The block holds
   the test command and the mutate globs.

## Run

Always pass the config path positionally. `--mutate` must come last, because
command-line-args consumes all trailing values.

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

- The HTML report lands at `reports/mutation/<group>.html`. Machine-readable
  statuses, including `statusReason` for ignored mutants, are in
  `reports/mutation/<group>-incremental.json`.
- `incremental: true` makes reruns near-free, because Stryker does not retest
  unchanged mutants. Delete the incremental JSON to force a full run.
- The first `npx` call downloads Stryker into the npm cache. This takes about
  30 s once, then the call is instant.

## Estimate before running

Cost is about `baseline_suite_time × mutant_count`, plus one baseline dry run. Get
the mutant count from the `Instrumented N source file(s) with M mutant(s)` line.
The line appears within seconds, before any mutant runs.

If the projected time is over about 30 minutes, stop. Then narrow the scope (fewer
files, line ranges, diff mode), or run Stryker as an explicit background job.
Never silently start a multi-hour run. Measurements on web-components:
`yarn test --group accordion` baseline about 3 s, and about 2.5 to 3 s per mutant.

## Cleanup and safety

- `inPlace: true` restores sources on normal exit and on Ctrl-C. A SIGKILL can
  leave a mutant applied. Before you declare any run done, require
  `git status --porcelain -- packages/*/src` (or the source root of the repo) to
  be empty. To recover, run `git checkout -- <path>`, or copy from the
  `.stryker-tmp/backup-*` directory that Stryker printed at startup.
- `.git/info/exclude` excludes the materialized files, `reports/mutation/` and
  `.stryker-tmp/`, so `git status` stays clean. Leave these files in place for
  reruns, because the incremental cache lives there. Remove them only when the
  user asks to remove every trace.
- Nothing touches `package.json`, `yarn.lock` or `node_modules`.

## Fallback if npx cannot be used

Use this fallback offline, with a blocked registry, or with broken npx resolution.
Install temporarily with `yarn add -D @stryker-mutator/core@9`. Run Stryker with
`node_modules/.bin/stryker run stryker-skill.conf.mjs …`. Then restore with
`git checkout -- package.json yarn.lock`.

The extra node_modules content is harmless. The next `yarn install` reconciles it.
The restore MUST run on every exit path. Re-check
`git status --porcelain package.json yarn.lock` in the done condition.
