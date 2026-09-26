// probe-example.cjs — a probe module for probe.cjs. Copy it next to your plan and edit it.
//
//   node ${CLAUDE_PLUGIN_ROOT}/scripts/probe.cjs --fn ./my-probe.cjs --out results-a.json \
//        --page /dev/menu-bar.html --themes base,lumo --dir both --arg widths=640,400,200
//
// `run` receives the Playwright page and the ctx that probe.cjs documents. Return plain data.
// Keep the sweep and the read apart, so that a compare of two result files stays readable.
'use strict';

const TAG = 'vaadin-menu-bar';

async function run(page, ctx) {
  await ctx.defined(TAG);
  const widths = (ctx.args.widths || '640,400,200').split(',').map(Number);
  await page.evaluate((tag) => {
    document.body.innerHTML = `<div id="w"><${tag}></${tag}></div>`;
    document.querySelector(tag).items = ['View', 'Edit', 'Share', 'Move', 'Archive'].map((text) => ({ text }));
  }, TAG);
  await ctx.settle(100);
  if (ctx.theme === 'lumo' && (await ctx.themeInjected(TAG)) !== '1') {
    throw new Error('Lumo CSS is not injected, the page needs a <title>');
  }
  const rows = [];
  for (const w of widths) {
    await page.evaluate((px) => {
      document.getElementById('w').style.width = `${px}px`;
    }, w);
    await ctx.settle(30);
    const layouts = ctx.layouts ? await ctx.layouts(() => page.evaluate((tag) => document.querySelector(tag).__detectOverflow?.(), TAG)) : null;
    const state = await page.evaluate((tag) => {
      const el = document.querySelector(tag);
      const buttons = [...el.querySelectorAll(`${tag}-button`)];
      return {
        host: +el.getBoundingClientRect().width.toFixed(1),
        hidden: buttons.filter((b) => b.style.visibility === 'hidden').length,
        overflow: buttons.some((b) => b.hasAttribute('slot') && !b.hasAttribute('hidden')),
      };
    }, TAG);
    rows.push({ w, ...state, layouts });
  }
  return rows;
}

function summary(rows) {
  return rows.map((r) => `${r.w}:${r.hidden}h`).join(' ');
}

module.exports = { run, summary };
