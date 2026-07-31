/**
 * Stryker mutation testing config (command runner), materialized by the
 * mutation-coverage skill — untracked, registered in .git/info/exclude.
 *
 * - `command` runner reruns the real Web Test Runner suite per mutant via
 *   `yarn test`, so the full browser environment is used — including the
 *   @web/test-runner-commands plugins (sendKeys/sendMouse/…) and esbuild.
 * - `inPlace` mutates the source in place (restored afterwards) so the
 *   monorepo's node_modules workspace symlinks stay intact.
 * - `concurrency: 1` avoids the Web Test Runner dev-server port race.
 *
 * Target a package with STRYKER_GROUP; scope further with `--mutate`.
 *
 * @type {import('@stryker-mutator/api/core').StrykerOptions}
 */
/* global process */
const group = process.env.STRYKER_GROUP || 'tabsheet';

export default {
  testRunner: 'command',
  commandRunner: {
    command: `yarn test --group ${group} --config wtr-stryker-skill.config.mjs`,
  },
  inPlace: true,
  mutate: [`packages/${group}/src/**/*.js`, `!packages/${group}/src/styles/**`],
  // Skip mutants in code the unit suite never covers (theme/style getters), so
  // they don't waste a run each and don't clutter the report as false survivors.
  plugins: ['./stryker-skill-ignore-plugin.mjs'],
  ignorers: ['untested-getters'],
  // Source is plain JS with nothing to strip; skip parsing every file in the
  // repo (avoids noisy HTML parse warnings on generated docs/coverage output).
  disableTypeChecks: false,
  // Keep Stryker's project scan off large generated/artifact trees.
  ignorePatterns: ['coverage', 'api-docs', 'dev'],
  concurrency: 1,
  reporters: ['html', 'clear-text', 'progress'],
  tempDirName: '.stryker-tmp',
  htmlReporter: { fileName: `reports/mutation/${group}.html` },
  // Reuse results across runs: unchanged mutants are not re-tested. Kept per
  // group so switching packages does not invalidate the cache.
  incremental: true,
  incrementalFile: `reports/mutation/${group}-incremental.json`,
};
