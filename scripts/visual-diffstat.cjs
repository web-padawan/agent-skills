#!/usr/bin/env node
// visual-diffstat.cjs — measure visual test screenshot diffs without a look at the PNGs.
//
// Usage:
//   node visual-diffstat.cjs [<dir | png>...] [--top N] [--sort pct|delta|name] [--tsv | --json]
//                            [--sheet <out.png>] [--scale 0.5] [--min-pct 0]
//   node visual-diffstat.cjs --before <a.png> --after <b.png> [--sheet <out.png>]
//   node visual-diffstat.cjs --git <tracked.png> [--sheet <out.png>]
//
// With no argument it walks packages/*/test/visual/**/screenshots/**/{failed,wip-failed}/ and
// pairs each <name>.png with <name>.png in the sibling baseline directory (failed → baseline,
// wip-failed → wip-baseline, else baseline). A directory argument narrows the walk. A PNG in a
// failed directory pairs the same way. --before/--after pairs two files. --git pairs a tracked
// PNG with its previous version: HEAD when the working tree changed it, else the parent of the
// last commit that touched it.
//
// One pair prints a metrics block. Several pairs print a table sorted by --sort (default pct):
//   pkg/theme/name  WxH  diff px  pct  maxΔ  R/G/B max  >16  bbox  bbox%  runner  hint
// `runner` is the pixelmatch count at the repo threshold (0.2), the number the test runner
// judges against failureThreshold 0.05%. `hint` is the mechanical part of the classification:
//   geometry     the sizes differ
//   content      maxΔ > 32 or more than 50 pixels with Δ > 16
//   noise?       maxΔ ≤ 4 and more than 5% of pixels differ (check the sample points)
//   subpixel     maxΔ ≤ 8 and at most 5% differ
//   region       maxΔ ≤ 32 inside a box under 25% of the canvas (look for a transition)
//   ambiguous    none of the above
// --sheet writes a contact sheet: one row per pair, tiles before | after | diff, a label above.
// --scale shrinks the tiles. --top limits the table and the sheet to the N largest diffs.
//
// Reads pngjs and pixelmatch from the repository node_modules. Writes only the --sheet file.
// Exit codes: 0 ok, also when nothing differs · 1 a pair could not be read · 2 usage error.
'use strict';
const fs = require('node:fs');
const path = require('node:path');
const { execSync } = require('node:child_process');

const opts = { inputs: [], top: 0, sort: 'pct', format: 'table', sheet: '', scale: 1, minPct: 0, before: '', after: '', git: '' };
const argv = process.argv.slice(2);
for (let i = 0; i < argv.length; i++) {
  const a = argv[i];
  const next = () => {
    if (argv[i + 1] === undefined) usage(`${a} requires a value`);
    return argv[++i];
  };
  if (a === '--help' || a === '-h') usage();
  else if (a === '--top') opts.top = Number(next());
  else if (a === '--sort') opts.sort = next();
  else if (a === '--tsv') opts.format = 'tsv';
  else if (a === '--json') opts.format = 'json';
  else if (a === '--sheet') opts.sheet = next();
  else if (a === '--scale') opts.scale = Number(next());
  else if (a === '--min-pct') opts.minPct = Number(next());
  else if (a === '--before') opts.before = next();
  else if (a === '--after') opts.after = next();
  else if (a === '--git') opts.git = next();
  else if (a.startsWith('--')) usage(`unknown flag ${a}`);
  else opts.inputs.push(a);
}
if ((opts.before && !opts.after) || (!opts.before && opts.after)) usage('--before and --after go together');
if (!['pct', 'delta', 'name'].includes(opts.sort)) usage('--sort takes pct, delta or name');

function usage(message) {
  const header = fs.readFileSync(__filename, 'utf8').split('\n').slice(1, 33).map((l) => l.replace(/^\/\/ ?/, '')).join('\n');
  if (message) console.error(`error: ${message}\n`);
  console.error(header);
  process.exit(message ? 2 : 0);
}

let root;
try {
  root = execSync('git rev-parse --show-toplevel', { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).trim();
} catch {
  root = process.cwd();
}
function load(name) {
  try {
    return require(require.resolve(name, { paths: [root, process.cwd()] }));
  } catch {
    return null;
  }
}
const pngjs = load('pngjs');
if (!pngjs) {
  console.error('error: pngjs is not installed in the repository, run yarn install');
  process.exit(1);
}
const { PNG } = pngjs;
const pixelmatch = load('pixelmatch');

// ── pairing ──────────────────────────────────────────────────────────
function baselineDirFor(failedDir) {
  const base = path.basename(failedDir);
  const candidates = [base.replace(/failed$/, 'baseline'), 'baseline'];
  for (const c of candidates) {
    const dir = path.join(path.dirname(failedDir), c);
    if (fs.existsSync(dir)) return dir;
  }
  return null;
}

function labelFor(file) {
  const rel = path.relative(root, file).split(path.sep);
  const pkg = rel[0] === 'packages' ? rel[1] : rel[0];
  const theme = (rel.find((s) => ['base', 'lumo', 'aura'].includes(s)) || 'base') + (rel.includes('dark') ? '/dark' : '');
  return `${pkg}/${theme}/${path.basename(file, '.png')}`;
}

function walkFailedDirs(start) {
  const out = [];
  const seen = new Set();
  const visit = (dir, depth) => {
    if (depth > 8 || !fs.existsSync(dir)) return;
    const base = path.basename(dir);
    if (/failed$/.test(base) && !seen.has(dir)) {
      seen.add(dir);
      out.push(dir);
      return;
    }
    if (base === 'node_modules' || base.startsWith('.')) return;
    for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
      if (e.isDirectory()) visit(path.join(dir, e.name), depth + 1);
    }
  };
  visit(start, 0);
  return out;
}

function pairsFromFailedDir(dir) {
  const baseline = baselineDirFor(dir);
  const pairs = [];
  for (const f of fs.readdirSync(dir).filter((n) => n.endsWith('.png') && !n.endsWith('-diff.png')).sort()) {
    const after = path.join(dir, f);
    const before = baseline ? path.join(baseline, f) : null;
    pairs.push({ label: labelFor(after), before: before && fs.existsSync(before) ? before : null, after, runnerDiff: path.join(dir, f.replace(/\.png$/, '-diff.png')) });
  }
  return pairs;
}

function pairFromGit(file) {
  const abs = path.resolve(file);
  const dir = path.dirname(abs);
  const git = (cmd) => execSync(`git -C "${dir}" ${cmd}`, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).trim();
  const rel = git(`ls-files --full-name -- "${abs}"`);
  if (!rel) return { error: `not tracked by git: ${file}` };
  let spec;
  let note;
  try {
    execSync(`git -C "${dir}" diff --quiet -- "${abs}"`, { stdio: 'ignore' });
    const last = git(`log --follow -1 --format=%H -- "${abs}"`);
    if (!last) return { error: `no git history: ${file}` };
    spec = `${last}^:${rel}`;
    note = `compare: ${last.slice(0, 10)} vs its parent`;
  } catch {
    spec = `HEAD:${rel}`;
    note = 'compare: working tree vs HEAD';
  }
  const tmp = path.join(fs.mkdtempSync(path.join(require('node:os').tmpdir(), 'visual-diffstat-')), 'before.png');
  try {
    fs.writeFileSync(tmp, execSync(`git -C "${dir}" show "${spec}"`, { stdio: ['ignore', 'pipe', 'ignore'], maxBuffer: 64 * 1024 * 1024 }));
  } catch {
    return { error: `no previous version of ${rel} (first baseline)`, first: true };
  }
  return { label: labelFor(abs), before: tmp, after: abs, note };
}

// ── measurement ──────────────────────────────────────────────────────
function readPng(file) {
  return PNG.sync.read(fs.readFileSync(file));
}

function measure(pair) {
  const a = readPng(pair.before);
  const b = readPng(pair.after);
  const m = { label: pair.label, before: pair.before, after: pair.after, dim: `${b.width}x${b.height}` };
  if (a.width !== b.width || a.height !== b.height) {
    Object.assign(m, { geometry: `${a.width}x${a.height} → ${b.width}x${b.height}`, hint: 'geometry', pct: 100, maxDelta: 255 });
    return m;
  }
  const { width: W, height: H } = a;
  const total = W * H;
  let count = 0;
  let high = 0;
  let maxDelta = 0;
  const chMax = [0, 0, 0];
  const hist = new Array(256).fill(0);
  let minX = W, minY = H, maxX = -1, maxY = -1;
  for (let y = 0; y < H; y++) {
    for (let x = 0; x < W; x++) {
      const i = (y * W + x) * 4;
      let d = 0;
      for (let c = 0; c < 3; c++) {
        const dc = Math.abs(a.data[i + c] - b.data[i + c]);
        if (dc > chMax[c]) chMax[c] = dc;
        if (dc > d) d = dc;
      }
      if (d > 0) {
        count++;
        hist[d]++;
        if (d > 16) high++;
        if (d > maxDelta) maxDelta = d;
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
      }
    }
  }
  const bbox = count ? { x: minX, y: minY, w: maxX - minX + 1, h: maxY - minY + 1 } : null;
  const bboxPct = bbox ? (100 * bbox.w * bbox.h) / total : 0;
  const pct = (100 * count) / total;
  const px = (img, x, y) => {
    const i = (y * W + x) * 4;
    return [img.data[i], img.data[i + 1], img.data[i + 2]];
  };
  const samplePoints = [['TL', 5, 5], ['TR', W - 6, 5], ['BL', 5, H - 6], ['BR', W - 6, H - 6], ['CENTER', W >> 1, H >> 1], ['Q1', W >> 2, H >> 2], ['Q3', (3 * W) >> 2, (3 * H) >> 2]];
  const samples = samplePoints.filter(([, x, y]) => x >= 0 && y >= 0).map(([name, x, y]) => ({ name, x, y, before: px(a, x, y), after: px(b, x, y) }));
  let runner = null;
  if (pixelmatch) {
    runner = pixelmatch(a.data, b.data, null, W, H, { threshold: 0.2 });
  }
  let hint = 'ambiguous';
  if (maxDelta > 32 || high >= 50) hint = 'content';
  else if (maxDelta <= 4 && pct > 5) hint = 'noise?';
  else if (maxDelta <= 8 && pct <= 5) hint = 'subpixel';
  else if (bboxPct < 25) hint = 'region';
  if (count === 0) hint = 'identical';
  Object.assign(m, { total, count, pct, maxDelta, chMax, high, bbox, bboxPct, runner, runnerPct: runner === null ? null : (100 * runner) / total, hist, samples, hint });
  return m;
}

// ── output ───────────────────────────────────────────────────────────
const f1 = (n) => (Math.round(n * 100) / 100).toFixed(2);
const bboxText = (m) => (m.bbox ? `${m.bbox.w}x${m.bbox.h}@${m.bbox.x},${m.bbox.y}` : '-');

function printBlock(m, note) {
  if (note) console.log(note);
  console.log(`LABEL ${m.label}`);
  console.log(`BEFORE ${m.before}`);
  console.log(`AFTER ${m.after}`);
  if (m.geometry) {
    console.log(`DIMENSION_MISMATCH ${m.geometry}`);
    console.log('HINT geometry');
    return;
  }
  console.log(`DIM ${m.dim}`);
  console.log(`DIFF_COUNT ${m.count}`);
  console.log(`DIFF_PCT ${f1(m.pct)}`);
  console.log(`MAX_DELTA ${m.maxDelta}`);
  console.log(`PER_CHANNEL_MAX R=${m.chMax[0]} G=${m.chMax[1]} B=${m.chMax[2]}`);
  console.log(`HIGH_DELTA_COUNT ${m.high}`);
  console.log(`BBOX ${m.bbox ? `${m.bbox.w}x${m.bbox.h} at (${m.bbox.x},${m.bbox.y})` : 'none'}`);
  console.log(`BBOX_AREA_PCT ${f1(m.bboxPct)}`);
  if (m.runner !== null) console.log(`RUNNER_DIFF ${m.runner} (${f1(m.runnerPct)}% at threshold 0.2, the runner fails above 0.05%)`);
  console.log(`DELTA_HIST_NONZERO ${m.hist.map((c, d) => (c ? `${d}:${c}` : null)).filter(Boolean).join(' ')}`);
  for (const s of m.samples) console.log(`SAMPLE ${s.name} (${s.x},${s.y}) before=${s.before.join(',')} after=${s.after.join(',')}`);
  console.log(`HINT ${m.hint}`);
}

function printTable(rows) {
  if (opts.format === 'json') {
    console.log(JSON.stringify(rows.map((m) => ({ ...m, hist: undefined })), null, 1));
    return;
  }
  const head = ['label', 'dim', 'diff px', 'pct', 'maxΔ', 'R/G/B', '>16', 'bbox', 'bbox%', 'runner', 'hint'];
  const lines = rows.map((m) =>
    m.error
      ? [m.label, '-', '-', '-', '-', '-', '-', '-', '-', '-', `error: ${m.error}`]
      : m.geometry
        ? [m.label, m.geometry, '-', '-', '-', '-', '-', '-', '-', '-', 'geometry']
        : [m.label, m.dim, String(m.count), f1(m.pct), String(m.maxDelta), m.chMax.join('/'), String(m.high), bboxText(m), f1(m.bboxPct), m.runner === null ? '-' : String(m.runner), m.hint],
  );
  if (opts.format === 'tsv') {
    console.log(head.join('\t'));
    for (const l of lines) console.log(l.join('\t'));
    return;
  }
  const widths = head.map((h, i) => Math.max(h.length, ...lines.map((l) => l[i].length)));
  const fmt = (cells) => cells.map((c, i) => (i === 0 || i === cells.length - 1 ? c.padEnd(widths[i]) : c.padStart(widths[i]))).join('  ');
  console.log(fmt(head));
  for (const l of lines) console.log(fmt(l));
}

// ── contact sheet ────────────────────────────────────────────────────
const FONT = {
  a: '01110100011000111111100011000110001', b: '11110100011000111110100011000111110', c: '01111100001000010000100001000001111', d: '11110100011000110001100011000111110',
  e: '11111100001000011110100001000011111', f: '11111100001000011110100001000010000', g: '01111100001000010111100011000101111', h: '10001100011000111111100011000110001',
  i: '01110001000010000100001000010001110', j: '00111000100001000010000101001001100', k: '10001100101010011000101001001010001', l: '10000100001000010000100001000011111',
  m: '10001110111010110001100011000110001', n: '10001110011010110011100011000110001', o: '01110100011000110001100011000101110', p: '11110100011000111110100001000010000',
  q: '01110100011000110001101011001001101', r: '11110100011000111110101001001010001', s: '01111100001000001110000010000111110', t: '11111001000010000100001000010000100',
  u: '10001100011000110001100011000101110', v: '10001100011000110001100010101000100', w: '10001100011000110101101011010101010', x: '10001100010101000100010101000110001',
  y: '10001100010101000100001000010000100', z: '11111000010001000100010001000011111', 0: '01110100011001110101110011000101110', 1: '00100011000010000100001000010001110',
  2: '01110100010000100010001000100011111', 3: '11111000100010000110000011000101110', 4: '00010001100101010010111110001000010', 5: '11111100001111000001000011000101110',
  6: '00110010001000011110100011000101110', 7: '11111000010001000100010000100001000', 8: '01110100011000101110100011000101110', 9: '01110100011000101111000010001001100',
  '-': '00000000000000011111000000000000000', '/': '00001000010001000100010001000010000', '.': '00000000000000000000000000110001100', _: '00000000000000000000000000000011111',
  ':': '00000011000110000000011000110000000', '%': '11001110010001000100010001001110011', ' ': '00000000000000000000000000000000000',
};

function drawText(png, text, x0, y0, scale, rgb) {
  let x = x0;
  for (const ch of text.toLowerCase()) {
    const glyph = FONT[ch] || FONT['.'];
    for (let r = 0; r < 7; r++) {
      for (let c = 0; c < 5; c++) {
        if (glyph[r * 5 + c] !== '1') continue;
        for (let dy = 0; dy < scale; dy++) for (let dx = 0; dx < scale; dx++) setPx(png, x + c * scale + dx, y0 + r * scale + dy, rgb);
      }
    }
    x += 6 * scale;
  }
}

function setPx(png, x, y, [r, g, b]) {
  if (x < 0 || y < 0 || x >= png.width || y >= png.height) return;
  const i = (y * png.width + x) * 4;
  png.data[i] = r;
  png.data[i + 1] = g;
  png.data[i + 2] = b;
  png.data[i + 3] = 255;
}

function scaled(img, scale) {
  if (scale === 1) return img;
  const w = Math.max(1, Math.round(img.width * scale));
  const h = Math.max(1, Math.round(img.height * scale));
  const out = new PNG({ width: w, height: h });
  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) {
      const sx = Math.min(img.width - 1, Math.floor(x / scale));
      const sy = Math.min(img.height - 1, Math.floor(y / scale));
      const si = (sy * img.width + sx) * 4;
      const di = (y * w + x) * 4;
      out.data.set(img.data.subarray(si, si + 4), di);
    }
  }
  return out;
}

function diffImage(a, b) {
  const out = new PNG({ width: a.width, height: a.height });
  if (pixelmatch && a.width === b.width && a.height === b.height) {
    pixelmatch(a.data, b.data, out.data, a.width, a.height, { threshold: 0.2, includeAA: true });
    return out;
  }
  out.data.fill(255);
  for (let i = 0; i < out.data.length; i += 4) {
    const d = Math.max(Math.abs(a.data[i] - b.data[i]), Math.abs(a.data[i + 1] - b.data[i + 1]), Math.abs(a.data[i + 2] - b.data[i + 2]));
    if (d) out.data.set([255, 0, 0, 255], i);
  }
  return out;
}

function writeSheet(rows, file) {
  const GAP = 8;
  const LABEL = 22;
  const tiles = rows
    .filter((m) => !m.error)
    .map((m) => {
      const a = scaled(readPng(m.before), opts.scale);
      const b = scaled(readPng(m.after), opts.scale);
      const d = a.width === b.width && a.height === b.height ? diffImage(a, b) : null;
      return { m, imgs: [a, b, d].filter(Boolean) };
    });
  if (!tiles.length) return;
  const labelOf = (m) => `${m.label}  ${m.geometry ? m.geometry : `${f1(m.pct)}% max ${m.maxDelta}`}  ${m.hint}  before / after / diff`;
  const rowW = Math.max(...tiles.map((t) => Math.max(t.imgs.reduce((s, i) => s + i.width + GAP, GAP), labelOf(t.m).length * 12 + 2 * GAP)));
  const rowH = (t) => Math.max(...t.imgs.map((i) => i.height)) + LABEL + GAP;
  const sheet = new PNG({ width: rowW, height: tiles.reduce((s, t) => s + rowH(t), GAP) });
  sheet.data.fill(238);
  for (let i = 3; i < sheet.data.length; i += 4) sheet.data[i] = 255;
  let y = GAP;
  for (const t of tiles) {
    drawText(sheet, labelOf(t.m), GAP, y, 2, [20, 20, 20]);
    let x = GAP;
    for (const img of t.imgs) {
      for (let yy = 0; yy < img.height; yy++) sheet.data.set(img.data.subarray(yy * img.width * 4, (yy + 1) * img.width * 4), ((y + LABEL + yy) * sheet.width + x) * 4);
      x += img.width + GAP;
    }
    y += rowH(t);
  }
  fs.mkdirSync(path.dirname(path.resolve(file)), { recursive: true });
  fs.writeFileSync(file, PNG.sync.write(sheet));
  console.log(`sheet: ${file} (${tiles.length} rows, ${sheet.width}x${sheet.height})`);
}

// ── main ─────────────────────────────────────────────────────────────
let pairs = [];
let note = '';
if (opts.before) {
  pairs = [{ label: `${path.basename(opts.before)} → ${path.basename(opts.after)}`, before: path.resolve(opts.before), after: path.resolve(opts.after) }];
} else if (opts.git) {
  const p = pairFromGit(opts.git);
  if (p.error) {
    console.log(p.error);
    process.exit(p.first ? 0 : 1);
  }
  note = p.note;
  pairs = [p];
} else {
  const inputs = opts.inputs.length ? opts.inputs : [path.join(root, 'packages')];
  for (const input of inputs) {
    const abs = path.resolve(input);
    if (!fs.existsSync(abs)) {
      console.error(`error: ${input} does not exist`);
      process.exit(2);
    }
    if (fs.statSync(abs).isFile()) {
      if (/failed$/.test(path.basename(path.dirname(abs)))) {
        const dir = path.dirname(abs);
        const baseline = baselineDirFor(dir);
        const before = baseline ? path.join(baseline, path.basename(abs)) : null;
        pairs.push({ label: labelFor(abs), before: before && fs.existsSync(before) ? before : null, after: abs });
      } else {
        const p = pairFromGit(abs);
        if (p.error) {
          console.log(p.error);
          process.exit(p.first ? 0 : 1);
        }
        note = p.note;
        pairs.push(p);
      }
    } else {
      for (const dir of walkFailedDirs(abs)) pairs.push(...pairsFromFailedDir(dir));
    }
  }
}

if (!pairs.length) {
  console.log('no failed screenshots found');
  process.exit(0);
}

let failed = false;
const rows = pairs.map((p) => {
  if (!p.before) {
    failed = true;
    return { label: p.label, error: 'no baseline' };
  }
  try {
    return measure(p);
  } catch (e) {
    failed = true;
    return { label: p.label, error: e.message };
  }
});

if (rows.length === 1 && !rows[0].error) {
  printBlock(rows[0], note);
  if (opts.sheet) writeSheet(rows, opts.sheet);
  process.exit(0);
}

const key = { pct: (m) => (m.error ? -1 : m.pct), delta: (m) => (m.error ? -1 : m.maxDelta), name: (m) => m.label }[opts.sort];
rows.sort((x, y) => (opts.sort === 'name' ? key(x).localeCompare(key(y)) : key(y) - key(x)));
let shown = rows.filter((m) => m.error || m.geometry || m.pct >= opts.minPct);
if (opts.top) shown = shown.slice(0, opts.top);
printTable(shown);
const measured = rows.filter((m) => !m.error);
const byHint = {};
for (const m of measured) byHint[m.hint] = (byHint[m.hint] || 0) + 1;
console.log(`${rows.length} pairs, ${measured.length} measured${rows.length - measured.length ? `, ${rows.length - measured.length} errors` : ''}: ${Object.entries(byHint).map(([k, v]) => `${k} ${v}`).join(', ')}`);
if (opts.sheet) writeSheet(shown, opts.sheet);
process.exit(failed ? 1 : 0);
