#!/usr/bin/env node
/**
 * Line-removal mutation testing.
 *
 * Deletes one line of a source file at a time and runs the test suite. A line
 * that can be removed while the suite stays green is a line no test asserts on,
 * which is either a test gap or dead code.
 *
 * Usage:
 *   node mutate.mjs <file> --test "<command>" [options]
 *
 * Examples:
 *   # Every line of the virtualizer adapter against the virtualizer tests
 *   node mutate.mjs packages/component-base/src/virtualizer-iron-list-adapter.js \
 *     --test 'yarn test --group component-base --glob="*virtualizer*"'
 *
 *   # Re-check only the lines that survived a previous run, e.g. after adding
 *   # tests. Lines are located by content, so they are still found after the
 *   # file has been edited.
 *   node mutate.mjs packages/component-base/src/virtualizer-iron-list-adapter.js \
 *     --test 'yarn test --group grid' --retest-survivors
 *
 *   # Run each mutant three times to tell real coverage from flaky failures
 *   node mutate.mjs src/foo.js --test 'yarn test --group foo' --lines 100-200 --repeat 3
 *
 * Options:
 *   --test <cmd>          Test command. Must exit non-zero when tests fail. Required.
 *   --lines <spec>        Restrict to these lines: "10-20,45,90-". Default: all.
 *   --repeat <n>          Run each mutant n times. A line counts as covered only
 *                         if every run fails; mixed results are reported as
 *                         "flaky", which usually means the failure is a timing
 *                         side effect rather than a real assertion. Default: 1.
 *   --retest-survivors    Only re-test the lines that survived in the log,
 *                         located by content instead of by line number.
 *   --resume              Skip lines already recorded in the log.
 *   --timeout <ms>        Per-run timeout. Default: 180000.
 *   --out <path>          JSONL log. Default: .mutate/<basename>.jsonl
 *   --no-syntax-check     Skip the `node --check` gate that discards removals
 *                         which cannot parse (needed for non-JS sources).
 *   --skip-baseline       Do not verify the suite is green first. Not advised:
 *                         a suite that already fails makes every mutant look
 *                         covered.
 *
 * Results per line:
 *   killed    at least one test failed - the line is covered
 *   SURVIVED  the suite stayed green - no test asserts on this line
 *   flaky     killed in some runs and not others (only with --repeat > 1)
 *   syntax    removing the line cannot parse, so it was not tested
 *   timeout   the test command hung and was killed
 */
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

function parseArgs(argv) {
  const opts = {
    lines: null,
    repeat: 1,
    retestSurvivors: false,
    resume: false,
    timeout: 180000,
    out: null,
    syntaxCheck: true,
    baseline: true,
  };
  const positional = [];

  let i = 0;
  const next = () => {
    i += 1;
    return argv[i];
  };

  while (i < argv.length) {
    const arg = argv[i];
    switch (arg) {
      case '--test':
        opts.test = next();
        break;
      case '--lines':
        opts.lines = next();
        break;
      case '--repeat':
        opts.repeat = Number(next());
        break;
      case '--timeout':
        opts.timeout = Number(next());
        break;
      case '--out':
        opts.out = next();
        break;
      case '--retest-survivors':
        opts.retestSurvivors = true;
        break;
      case '--resume':
        opts.resume = true;
        break;
      case '--no-syntax-check':
        opts.syntaxCheck = false;
        break;
      case '--skip-baseline':
        opts.baseline = false;
        break;
      case '-h':
      case '--help':
        opts.help = true;
        break;
      default:
        if (arg.startsWith('-')) {
          throw new Error(`Unknown option: ${arg}`);
        }
        positional.push(arg);
    }
    i += 1;
  }

  opts.file = positional[0];
  return opts;
}

/** Expands a spec like "10-20,45,90-" into a line-number predicate. */
function lineFilter(spec, lineCount) {
  if (!spec) {
    return () => true;
  }
  const ranges = spec.split(',').map((part) => {
    const [from, to] = part.split('-');
    return {
      from: Number(from),
      to: part.includes('-') ? Number(to || lineCount) : Number(from),
    };
  });
  return (line) => ranges.some((range) => line >= range.from && line <= range.to);
}

/** Lines worth mutating: skip blanks and comments, which change nothing. */
function isCandidate(text) {
  const trimmed = text.trim();
  if (!trimmed) {
    return false;
  }
  return !trimmed.startsWith('//') && !trimmed.startsWith('*') && !trimmed.startsWith('/*');
}

/**
 * How many identical lines precede this one. Together with the line text this
 * identifies a line by content, so it can still be found after the file has
 * moved on - which is what makes re-testing survivors possible.
 */
function occurrenceOf(lines, index) {
  const text = lines[index].trim();
  let n = 0;
  for (let i = 0; i < index; i += 1) {
    if (lines[i].trim() === text) {
      n += 1;
    }
  }
  return n;
}

/** The index of the nth line whose trimmed text matches, or -1. */
function locate(lines, text, occurrence) {
  let n = 0;
  for (let i = 0; i < lines.length; i += 1) {
    if (lines[i].trim() === text) {
      if (n === occurrence) {
        return i;
      }
      n += 1;
    }
  }
  return -1;
}

function readLog(logPath) {
  return fs
    .readFileSync(logPath, 'utf8')
    .split('\n')
    .filter(Boolean)
    .map((line) => JSON.parse(line));
}

function appendLog(logPath, record) {
  fs.appendFileSync(logPath, `${JSON.stringify(record)}\n`);
}

/** Whether the mutated source still parses, checked out of tree. */
function parses(source, originalPath) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'mutate-'));
  const tmp = path.join(dir, `${path.basename(originalPath)}.mjs`);
  try {
    fs.writeFileSync(tmp, source);
    return spawnSync(process.execPath, ['--check', tmp], { encoding: 'utf8' }).status === 0;
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
}

function printUsage() {
  const header = fs.readFileSync(new URL(import.meta.url), 'utf8').split('*/')[0];
  console.log(
    header
      .split('\n')
      .filter((line) => line.trim().startsWith('*'))
      .map((line) => line.replace(/^\s*\*\s?/u, ''))
      .join('\n')
      .trim(),
  );
}

function main() {
  const opts = parseArgs(process.argv.slice(2));

  if (opts.help || !opts.file || !opts.test) {
    printUsage();
    process.exit(opts.help ? 0 : 1);
  }

  const file = path.resolve(opts.file);
  const logPath = opts.out || path.join('.mutate', `${path.basename(file)}.jsonl`);
  fs.mkdirSync(path.dirname(logPath), { recursive: true });

  // A copy of the untouched source lives next to the log. If a previous run was
  // killed before it could restore the file, that mutant would otherwise be
  // baked in and silently corrupt every later run.
  const backupPath = `${logPath}.orig`;
  if (fs.existsSync(backupPath)) {
    const backup = fs.readFileSync(backupPath, 'utf8');
    if (fs.readFileSync(file, 'utf8') !== backup) {
      console.log(`! ${path.basename(file)} differs from the backup of an interrupted run - restoring it`);
      fs.writeFileSync(file, backup);
    }
  } else {
    fs.copyFileSync(file, backupPath);
  }

  const pristine = fs.readFileSync(file, 'utf8');
  const lines = pristine.split('\n');

  const restore = () => {
    if (fs.readFileSync(file, 'utf8') !== pristine) {
      fs.writeFileSync(file, pristine);
    }
  };
  // Restore on every exit path, including Ctrl-C and an unhandled throw.
  process.on('exit', restore);
  ['SIGINT', 'SIGTERM', 'SIGHUP'].forEach((signal) => {
    process.on(signal, () => {
      restore();
      process.exit(1);
    });
  });

  const runTests = () => {
    const res = spawnSync(opts.test, {
      shell: true,
      cwd: process.cwd(),
      encoding: 'utf8',
      timeout: opts.timeout,
      killSignal: 'SIGKILL',
    });
    const output = `${res.stdout || ''}${res.stderr || ''}`;
    const counts = output.match(/\d+ passed, \d+ failed/gu);
    return {
      timedOut: Boolean(res.signal || res.error),
      passed: res.status === 0,
      counts: counts ? counts[counts.length - 1] : null,
      // web-test-runner marks each failing test with a cross
      failedTests: [...output.matchAll(/❌\s+(.+)/gu)].map((match) => match[1].trim()),
      output,
    };
  };

  if (opts.baseline) {
    process.stdout.write('Checking the baseline is green... ');
    const baseline = runTests();
    if (!baseline.passed) {
      console.log('FAILED\n');
      console.log(baseline.output.slice(-4000));
      console.log(
        '\nThe suite fails before anything was mutated, so every mutant would look covered.\n' +
          'Fix the suite first, or pass --skip-baseline if you know what you are doing.',
      );
      process.exit(1);
    }
    console.log(`ok (${baseline.counts || 'no counts parsed'})`);
  }

  let targets;
  if (opts.retestSurvivors) {
    if (!fs.existsSync(logPath)) {
      console.log(`No log at ${logPath} to take survivors from.`);
      process.exit(1);
    }
    targets = readLog(logPath)
      .filter((entry) => entry.result === 'SURVIVED')
      .map((entry) => ({ ...entry, line: locate(lines, entry.text.trim(), entry.occurrence) + 1 }))
      .filter((entry) => {
        if (entry.line === 0) {
          console.log(`- no longer in the source: ${entry.text.trim()}`);
          return false;
        }
        return true;
      });
    // Start a fresh log so re-test results do not mix with the previous ones.
    fs.renameSync(logPath, `${logPath}.previous`);
  } else {
    const inRange = lineFilter(opts.lines, lines.length);
    const done = new Set(opts.resume && fs.existsSync(logPath) ? readLog(logPath).map((entry) => entry.line) : []);
    targets = lines
      .map((text, index) => ({ line: index + 1, text, occurrence: occurrenceOf(lines, index) }))
      .filter((target) => isCandidate(target.text) && inRange(target.line) && !done.has(target.line));
  }

  console.log(`Mutating ${targets.length} lines of ${path.relative(process.cwd(), file)}\n`);

  const tally = {};
  const survivors = [];

  targets.forEach((target, index) => {
    const mutant = lines.filter((_, i) => i !== target.line - 1).join('\n');
    const record = { line: target.line, text: target.text, occurrence: target.occurrence };

    if (opts.syntaxCheck && !parses(mutant, file)) {
      // Removing this line leaves code that cannot parse (a closing brace, an
      // `if (...) {` header, part of a multi-line expression), so there is
      // nothing to learn from running the tests.
      record.result = 'syntax';
      appendLog(logPath, record);
      tally.syntax = (tally.syntax || 0) + 1;
      return;
    }

    fs.writeFileSync(file, mutant);
    const runs = [];
    for (let run = 0; run < opts.repeat; run += 1) {
      runs.push(runTests());
    }
    fs.writeFileSync(file, pristine);

    const killedRuns = runs.filter((run) => !run.passed).length;
    if (runs.some((run) => run.timedOut)) {
      record.result = 'timeout';
    } else if (killedRuns === runs.length) {
      record.result = 'killed';
    } else if (killedRuns === 0) {
      record.result = 'SURVIVED';
    } else {
      record.result = 'flaky';
      record.killedRuns = `${killedRuns}/${runs.length}`;
    }
    record.counts = runs[runs.length - 1].counts;
    record.failedTests = [...new Set(runs.flatMap((run) => run.failedTests))].slice(0, 5);

    appendLog(logPath, record);
    tally[record.result] = (tally[record.result] || 0) + 1;
    if (record.result === 'SURVIVED') {
      survivors.push(record);
    }

    const progress = `[${index + 1}/${targets.length}]`;
    const text = target.text.trim().slice(0, 60);
    console.log(`${progress} L${target.line}\t${record.result}\t${record.counts || ''}\t${text}`);
    if (record.failedTests.length) {
      console.log(`${' '.repeat(progress.length)}   └─ ${record.failedTests.join(' | ')}`);
    }
  });

  const summary = Object.entries(tally)
    .map(([result, count]) => `${result}: ${count}`)
    .join('  ');
  console.log(`\n${summary}`);
  if (survivors.length) {
    console.log(`\n${survivors.length} line(s) no test asserts on:`);
    survivors.forEach((survivor) => console.log(`  L${survivor.line}  ${survivor.text.trim()}`));
  }
  console.log(`\nLog: ${logPath}`);
  fs.rmSync(backupPath, { force: true });
}

main();
