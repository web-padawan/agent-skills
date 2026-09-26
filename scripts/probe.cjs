#!/usr/bin/env node
// probe.cjs — run one browser probe module against a dev page, per theme and direction.
//
// Usage:
//   node probe.cjs --fn <probe.cjs> --out <results.json> [--page /dev/<component>.html]
//                  [--port 8765] [--themes base,lumo,aura] [--dir ltr|rtl|both]
//                  [--engine chromium|firefox|webkit] [--patch <page-script.js>]
//                  [--viewport 1024x768] [--timeout 60] [--arg key=value]... [--force] [--no-server]
//
// The probe module exports `run(page, ctx)` (or `{ run, summary }`). `run` returns any JSON
// value, usually an array of rows. `summary(value)` returns the one line to print per variant.
// See probe-example.cjs next to this file.
//
// ctx has: theme, dir, args (from --arg), root (repo root), url,
//   settle(ms = 0)          two animation frames, then an optional timeout
//   defined(tag)            waits for customElements.get(tag)
//   layouts(fn)             forced layout count of `await fn()` via CDP (chromium only, else null)
//   themeInjected(tag)      reads --_lumo-vaadin-<tag>-inject on the first <tag> (1 means Lumo CSS is on)
//   errors                  page errors and console errors collected so far
//
// --timeout caps every navigation and wait, in seconds, so a broken page fails instead of hanging.
// The harness starts the dev server through dev-server.sh when nothing answers on the port,
// and refuses to overwrite an existing --out file unless --force is given. The output holds
// `meta` (page, engine, git head, dirty flag, patch, args, time) and `results[<theme>/<dir>]`.
// Compare two outputs with probe-compare.cjs.
//
// Exit codes: 0 ok · 1 usage or environment error · 2 the probe threw.
'use strict';
const fs = require('node:fs');
const path = require('node:path');
const { execSync, spawnSync } = require('node:child_process');

const args = { themes: 'base', dir: 'ltr', engine: 'chromium', port: '8765', page: '/dev/', viewport: '1024x768', timeout: '60', arg: [] };
const argv = process.argv.slice(2);
for (let i = 0; i < argv.length; i++) {
  const a = argv[i];
  if (!a.startsWith('--')) usage(`unexpected argument: ${a}`);
  const key = a.slice(2);
  if (key === 'force' || key === 'no-server' || key === 'help') {
    args[key] = true;
    continue;
  }
  const value = argv[++i];
  if (value === undefined) usage(`--${key} requires a value`);
  if (key === 'arg') args.arg.push(value);
  else args[key] = value;
}
if (args.help) usage();
if (!args.fn || !args.out) usage('--fn and --out are required');

function usage(message) {
  const header = fs.readFileSync(__filename, 'utf8').split('\n').slice(1, 26).map((l) => l.replace(/^\/\/ ?/, '')).join('\n');
  if (message) console.error(`error: ${message}\n`);
  console.error(header);
  process.exit(message ? 1 : 0);
}

const root = execSync('git rev-parse --show-toplevel', { encoding: 'utf8' }).trim();
const outFile = path.resolve(args.out);
if (fs.existsSync(outFile) && !args.force) {
  console.error(`error: ${outFile} exists, pass --force to overwrite`);
  process.exit(1);
}
const probe = require(path.resolve(args.fn));
const run = typeof probe === 'function' ? probe : probe.run;
if (typeof run !== 'function') {
  console.error(`error: ${args.fn} must export run(page, ctx)`);
  process.exit(1);
}
const summary = typeof probe.summary === 'function' ? probe.summary : defaultSummary;

let pw;
try {
  pw = require(require.resolve('playwright-core', { paths: [root] }));
} catch {
  try {
    pw = require(require.resolve('playwright', { paths: [root] }));
  } catch {
    console.error('error: neither playwright-core nor playwright is installed in the repo');
    process.exit(1);
  }
}

if (!args['no-server']) {
  const server = spawnSync(path.join(__dirname, 'dev-server.sh'), ['ensure', '--port', args.port, '--path', args.page], {
    cwd: root,
    encoding: 'utf8',
  });
  process.stderr.write(server.stdout);
  if (server.status !== 0) {
    process.stderr.write(server.stderr);
    process.exit(1);
  }
}

const themes = args.themes.split(',').map((t) => t.trim()).filter(Boolean);
const dirs = args.dir === 'both' ? ['ltr', 'rtl'] : [args.dir];
const [vw, vh] = args.viewport.split('x').map(Number);
const patch = args.patch ? fs.readFileSync(path.resolve(args.patch), 'utf8') : null;
const probeArgs = Object.fromEntries(args.arg.map((kv) => kv.split(/=(.*)/s).slice(0, 2)));

function defaultSummary(value) {
  if (Array.isArray(value)) return `${value.length} rows`;
  if (value && typeof value === 'object') return `${Object.keys(value).length} keys`;
  return String(value);
}

(async () => {
  const browser = await pw[args.engine].launch();
  const results = {};
  const errors = {};
  let failed = false;
  for (const theme of themes) {
    for (const dir of dirs) {
      const variant = `${theme}/${dir}`;
      const page = await browser.newPage({ viewport: { width: vw, height: vh } });
      page.setDefaultTimeout(Number(args.timeout) * 1000);
      const collected = [];
      page.on('pageerror', (e) => collected.push(`pageerror: ${e.message}`));
      page.on('console', (m) => {
        if (m.type() === 'error') collected.push(`console: ${m.text()}`);
      });
      const url = `http://localhost:${args.port}${args.page}${theme === 'base' ? '' : `?theme=${theme}`}`;
      await page.goto(url, { waitUntil: 'load' });
      if (dir === 'rtl') await page.evaluate(() => document.documentElement.setAttribute('dir', 'rtl'));
      const ctx = {
        theme,
        dir,
        args: probeArgs,
        root,
        url,
        errors: collected,
        settle: (ms = 0) =>
          page.evaluate((t) => new Promise((r) => requestAnimationFrame(() => requestAnimationFrame(() => setTimeout(r, t)))), ms),
        defined: (tag) => page.waitForFunction((t) => Boolean(customElements.get(t)), tag),
        layouts: null,
        themeInjected: (tag) =>
          page.evaluate((t) => {
            const el = document.querySelector(t);
            return el ? getComputedStyle(el).getPropertyValue(`--_lumo-vaadin-${t.replace(/^vaadin-/, '')}-inject`).trim() : null;
          }, tag),
      };
      if (args.engine === 'chromium') {
        const cdp = await page.context().newCDPSession(page);
        await cdp.send('Performance.enable');
        const count = async () => (await cdp.send('Performance.getMetrics')).metrics.find((m) => m.name === 'LayoutCount').value;
        ctx.layouts = async (fn) => {
          const before = await count();
          await fn();
          return (await count()) - before;
        };
      }
      await ctx.settle(50);
      if (patch) await page.evaluate(patch);
      try {
        results[variant] = await run(page, ctx);
        console.log(`${variant.padEnd(12)} ${summary(results[variant], ctx)}${collected.length ? `  errors=${collected.length}` : ''}`);
      } catch (e) {
        failed = true;
        results[variant] = null;
        console.log(`${variant.padEnd(12)} THREW ${e.message}`);
      }
      if (collected.length) errors[variant] = collected;
      await page.close();
    }
  }
  await browser.close();
  const git = (cmd) => execSync(cmd, { cwd: root, encoding: 'utf8' }).trim();
  const meta = {
    page: args.page,
    port: Number(args.port),
    engine: args.engine,
    themes,
    dirs,
    fn: path.relative(root, path.resolve(args.fn)),
    patch: args.patch ? path.relative(root, path.resolve(args.patch)) : null,
    args: probeArgs,
    head: git('git rev-parse --short HEAD'),
    branch: git('git branch --show-current'),
    dirty: git('git status --porcelain --untracked-files=no') !== '',
    time: new Date().toISOString(),
  };
  fs.mkdirSync(path.dirname(outFile), { recursive: true });
  fs.writeFileSync(outFile, `${JSON.stringify({ meta, errors, results }, null, 1)}\n`);
  console.log(`wrote ${outFile} (head ${meta.head}${meta.dirty ? ', dirty tree' : ''})`);
  process.exit(failed ? 2 : 0);
})().catch((e) => {
  console.error(e);
  process.exit(2);
});
