#!/usr/bin/env node
// Screenshot a route at every rung in the active viewport ladder, and report
// what a screenshot alone cannot show: console errors, failed requests, and
// horizontal overflow.
//
//   node runtime/shoot.mjs http://localhost:4319/            # default ladder
//   node runtime/shoot.mjs http://localhost:4319/cart --rungs compact,expanded
//   node runtime/shoot.mjs http://localhost:4319/ --out /tmp/shots
//
// The ladder is READ FROM CONFIG, never hardcoded here. Resolution order:
//   1. --rungs <names>
//   2. $APP_BOX_LADDER            (e.g. "compact,medium")
//   3. the artifact's _d_meta.json -> ladder
//   4. every rung defined in ladder.json
//
// Exits non-zero if any rung produced a console error, a failed request, or
// horizontal overflow. A screenshot that was never inspected is not
// verification — this makes the machine-checkable part fail loudly.
import { existsSync, mkdirSync, readFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = dirname(fileURLToPath(import.meta.url));
const LADDER = JSON.parse(readFileSync(join(HERE, 'ladder.json'), 'utf8')).rungs;

const args = process.argv.slice(2);
const url = args.find((a) => !a.startsWith('--'));
if (!url) {
  console.error('usage: shoot.mjs <url> [--rungs a,b] [--out dir] [--artifact dir]');
  process.exit(2);
}
const flag = (n) => { const i = args.indexOf(`--${n}`); return i < 0 ? null : args[i + 1]; };
const outDir = resolve(flag('out') || '/tmp/app-box-shots');
const artifact = flag('artifact');

function resolveRungs() {
  const named = flag('rungs') || process.env.APP_BOX_LADDER;
  if (named) return named.split(',').map((s) => s.trim()).filter(Boolean);
  if (artifact) {
    const meta = join(artifact, '_d_meta.json');
    if (existsSync(meta)) {
      const m = JSON.parse(readFileSync(meta, 'utf8'));
      if (Array.isArray(m.ladder) && m.ladder.length) return m.ladder;
    }
  }
  return Object.keys(LADDER);
}

const rungs = resolveRungs();
const unknown = rungs.filter((r) => !LADDER[r]);
if (unknown.length) {
  console.error(`unknown rung(s): ${unknown.join(', ')} — defined: ${Object.keys(LADDER).join(', ')}`);
  process.exit(2);
}

mkdirSync(outDir, { recursive: true });
const { chromium } = await import('playwright');
const browser = await chromium.launch();
const slug = url.replace(/^https?:\/\/[^/]+/, '').replace(/[^\w]+/g, '_').replace(/^_|_$/g, '') || 'root';

let bad = 0;
console.log(`ladder: ${rungs.join(', ')}`);
for (const name of rungs) {
  const { width, height } = LADDER[name];
  const page = await browser.newPage({ viewport: { width, height } });
  const problems = [];
  page.on('console', (m) => m.type() === 'error' && problems.push(`console: ${m.text()}`));
  page.on('pageerror', (e) => problems.push(`pageerror: ${e.message}`));
  page.on('requestfailed', (r) => problems.push(`request failed: ${r.url()}`));
  page.on('response', (r) => r.status() >= 400 && problems.push(`HTTP ${r.status()}: ${r.url()}`));

  const path = join(outDir, `${slug}-${name}-${width}.png`);
  try {
    const res = await page.goto(url, { waitUntil: 'networkidle', timeout: 20000 });
    if (!res || res.status() >= 400) problems.push(`page HTTP ${res ? res.status() : 'no response'}`);
    await page.screenshot({ path, fullPage: true });
    const o = await page.evaluate(() => ({
      scrollW: document.documentElement.scrollWidth,
      clientW: document.documentElement.clientWidth,
    }));
    if (o.scrollW > o.clientW) problems.push(`horizontal overflow: ${o.scrollW}px in ${o.clientW}px`);
  } catch (e) {
    problems.push(`navigation: ${e.message.split('\n')[0]}`);
  }
  await page.close();

  if (problems.length) {
    bad++;
    console.log(`  FAIL ${name.padEnd(9)} ${width}x${height}  ${path}`);
    for (const p of problems) console.log(`         ${p}`);
  } else {
    console.log(`  ok   ${name.padEnd(9)} ${width}x${height}  ${path}`);
  }
}
await browser.close();

console.log(bad
  ? `\n${bad}/${rungs.length} rung(s) have problems — fix before surfacing.`
  : `\n${rungs.length} rung(s) clean. Now READ the images — machine checks do not judge layout.`);
process.exit(bad ? 1 : 0);
