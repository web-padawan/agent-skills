#!/usr/bin/env node
/* eslint-env node */
/**
 * Run mutation testing only on the lines changed on this branch, per package.
 *
 * The command runner reruns the whole suite per mutant, so cost scales with
 * mutant count. For a PR we only care about the diff, so this narrows Stryker's
 * `mutate` to the changed line ranges (its `file.js:startLine-endLine` syntax).
 * Changed files are grouped by package and Stryker is run once per package with
 * STRYKER_GROUP set, so each package mutates its own changed lines and runs its
 * own tests (including sendKeys/sendMouse ones).
 *
 * Changes are compared against the merge-base with the base ref, including
 * uncommitted work, so it works both locally and in CI.
 *
 * Usage:
 *   node stryker-diff.mjs [--base <ref>] [--config <stryker-config>] [--dry-run]
 *
 * Options:
 *   --base <ref>      Base ref to diff against. Default: origin/main.
 *   --config <path>   Stryker config file to run with. Default: the repo's
 *                     committed stryker.conf.js when present, otherwise the
 *                     materialized stryker-skill.conf.mjs.
 *   --dry-run         Only print the changed ranges per package; run nothing.
 */
import { execFileSync, spawnSync } from 'node:child_process';
import fs from 'node:fs';

const args = process.argv.slice(2);
const flag = (name) => {
  const index = args.indexOf(name);
  return index === -1 ? undefined : (args[index + 1] ?? true);
};
const baseRef = flag('--base') ?? 'origin/main';
const dryRun = args.includes('--dry-run');
const configFile =
  flag('--config') ?? (fs.existsSync('stryker.conf.js') ? 'stryker.conf.js' : 'stryker-skill.conf.mjs');

const git = (gitArgs) => execFileSync('git', gitArgs, { encoding: 'utf8' });

// Only mutate production source, never test files or CSS-in-JS style modules.
const mutableSource = /^packages\/([^/]+)\/src\/.*\.js$/u;
const isMutableSource = (file) => mutableSource.test(file) && !file.includes('/src/styles/');

let mergeBase;
try {
  mergeBase = git(['merge-base', baseRef, 'HEAD']).trim();
} catch {
  console.error(`Could not resolve merge-base with "${baseRef}". Fetch it first (e.g. git fetch origin main).`);
  process.exit(1);
}

// `-U0` gives zero context lines, so hunk headers map exactly to changed lines.
// Scope to `packages` and let isMutableSource() do the precise filtering (git
// pathspecs can't express "src/*.js but not src/styles" reliably).
const diff = git(['diff', '-U0', '--diff-filter=ACMR', mergeBase, '--', 'packages']);

// Group changed line ranges by package.
const rangesByPackage = new Map();
let currentFile = null;
for (const line of diff.split('\n')) {
  const fileMatch = /^\+\+\+ b\/(.+)$/u.exec(line);
  if (fileMatch) {
    currentFile = fileMatch[1];
    continue;
  }
  const hunkMatch = /^@@ -\d+(?:,\d+)? \+(\d+)(?:,(\d+))? @@/u.exec(line);
  if (hunkMatch && currentFile && isMutableSource(currentFile)) {
    const start = Number(hunkMatch[1]);
    const count = hunkMatch[2] === undefined ? 1 : Number(hunkMatch[2]);
    if (count > 0) {
      const pkg = mutableSource.exec(currentFile)[1];
      const ranges = rangesByPackage.get(pkg) ?? [];
      ranges.push(`${currentFile}:${start}-${start + count - 1}`);
      rangesByPackage.set(pkg, ranges);
    }
  }
}

if (rangesByPackage.size === 0) {
  console.log(`No mutable source changes vs ${baseRef} (merge-base ${mergeBase.slice(0, 9)}). Nothing to mutate.`);
  process.exit(0);
}

let failed = false;
for (const [pkg, ranges] of rangesByPackage) {
  console.log(`\n=== ${pkg}: ${ranges.length} changed range(s) ===`);
  ranges.forEach((r) => console.log(`  ${r}`));
  if (dryRun) {
    continue;
  }
  // `--mutate` must be last: command-line-args consumes all trailing values.
  const result = spawnSync('npx', ['--yes', '--package', '@stryker-mutator/core@9', 'stryker', 'run', configFile, '--mutate', ...ranges], {
    stdio: 'inherit',
    env: { ...process.env, STRYKER_GROUP: pkg },
  });
  if (result.status !== 0) {
    failed = true;
  }
}

process.exit(failed ? 1 : 0);
