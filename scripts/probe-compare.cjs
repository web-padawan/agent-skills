#!/usr/bin/env node
// probe-compare.cjs — diff two probe.cjs result files.
//
// Usage: node probe-compare.cjs <a.json> <b.json> [--tolerance 0] [--max 40]
//
// Walks `results` of both files. Arrays align by index, objects by key. A number differs when
// |a - b| > tolerance. Prints one line per leaf difference, up to --max, as
//   <variant> <path>: <a> → <b>
// then one count line per variant and a meta line that names the git head of each side.
// A variant that exists on one side only is reported, never skipped.
//
// Exit codes: 0 identical within tolerance · 1 differences · 2 usage error.
'use strict';
const fs = require('node:fs');
const path = require('node:path');

const files = [];
let tolerance = 0;
let max = 40;
const argv = process.argv.slice(2);
for (let i = 0; i < argv.length; i++) {
  if (argv[i] === '--tolerance') tolerance = Number(argv[++i]);
  else if (argv[i] === '--max') max = Number(argv[++i]);
  else if (argv[i] === '--help') usage();
  else files.push(argv[i]);
}
if (files.length !== 2) usage('pass exactly two result files');

function usage(message) {
  if (message) console.error(`error: ${message}\n`);
  console.error(fs.readFileSync(__filename, 'utf8').split('\n').slice(1, 12).map((l) => l.replace(/^\/\/ ?/, '')).join('\n'));
  process.exit(message ? 2 : 0);
}

const [A, B] = files.map((f) => JSON.parse(fs.readFileSync(path.resolve(f), 'utf8')));
const diffs = [];

function walk(a, b, at, variant) {
  if (a === b) return;
  if (typeof a === 'number' && typeof b === 'number') {
    if (Math.abs(a - b) > tolerance && !(Number.isNaN(a) && Number.isNaN(b))) diffs.push([variant, at, a, b]);
    return;
  }
  if (Array.isArray(a) && Array.isArray(b)) {
    const n = Math.max(a.length, b.length);
    for (let i = 0; i < n; i++) walk(a[i], b[i], `${at}[${i}]`, variant);
    return;
  }
  if (a && b && typeof a === 'object' && typeof b === 'object') {
    for (const k of new Set([...Object.keys(a), ...Object.keys(b)])) walk(a[k], b[k], at ? `${at}.${k}` : k, variant);
    return;
  }
  diffs.push([variant, at, a, b]);
}

const show = (v) => (v === undefined ? '(absent)' : JSON.stringify(v));
const variants = new Set([...Object.keys(A.results || {}), ...Object.keys(B.results || {})]);
for (const v of variants) walk(A.results?.[v], B.results?.[v], '', v);

for (const [variant, at, a, b] of diffs.slice(0, max)) console.log(`${variant.padEnd(12)} ${at || '(root)'}: ${show(a)} → ${show(b)}`);
if (diffs.length > max) console.log(`… ${diffs.length - max} more`);
for (const v of variants) {
  const n = diffs.filter((d) => d[0] === v).length;
  console.log(`${v.padEnd(12)} ${n === 0 ? 'identical' : `${n} differences`}`);
}
const side = (r, f) => `${path.basename(f)} head=${r.meta?.head ?? '?'}${r.meta?.dirty ? '+dirty' : ''}${r.meta?.patch ? ` patch=${r.meta.patch}` : ''}`;
console.log(`meta: ${side(A, files[0])} | ${side(B, files[1])}${tolerance ? ` | tolerance ${tolerance}` : ''}`);
if (A.meta?.head && A.meta.head === B.meta?.head && !A.meta.patch && !B.meta.patch && !A.meta.dirty && !B.meta.dirty) {
  console.log('note: both sides record the same clean head, so this compares two runs of one tree');
}
process.exit(diffs.length ? 1 : 0);
