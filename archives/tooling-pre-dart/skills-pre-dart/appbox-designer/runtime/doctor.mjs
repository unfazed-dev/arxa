#!/usr/bin/env node
// Preflight for the designer's own machine.
//
// This file must run with ZERO dependencies installed — that is the whole
// point. It names what is missing instead of letting a render fail obscurely
// three steps later.
//
//   node runtime/doctor.mjs
//
// Exits 0 when everything the render and console gates need is present,
// 1 otherwise. A missing dependency is a hard failure, not a warning: a
// skipped gate reported as a pass is the defect this project exists to avoid.
import { existsSync, readFileSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = dirname(fileURLToPath(import.meta.url));
const rows = [];
const add = (ok, name, detail, fix) => rows.push({ ok, name, detail, fix });

// --- Node ------------------------------------------------------------------
const major = Number(process.versions.node.split('.')[0]);
add(major >= 20, 'Node ≥ 20', `found ${process.version}`,
    'install Node 20 or newer (nodejs.org, nvm, or your package manager)');

// --- npm dependencies ------------------------------------------------------
const pkg = JSON.parse(readFileSync(join(HERE, 'package.json'), 'utf8'));
const nm = join(HERE, 'node_modules');
const haveNm = existsSync(nm);
add(haveNm, 'runtime/node_modules', haveNm ? 'installed' : 'absent',
    `cd ${HERE} && npm install`);

for (const dep of Object.keys({ ...pkg.dependencies, ...pkg.devDependencies })) {
  const p = join(nm, ...dep.split('/'));
  add(existsSync(p), `  ${dep}`, existsSync(p) ? 'ok' : 'missing',
      `cd ${HERE} && npm install`);
}

// --- Playwright browser ----------------------------------------------------
// The package alone is not enough — the render and console gates need a
// downloaded chromium.
let browser = false, browserDetail = 'playwright not installed';
if (existsSync(join(nm, 'playwright'))) {
  try {
    execFileSync('npx', ['--no-install', 'playwright', '--version'],
                 { cwd: HERE, stdio: 'pipe' });
    const { chromium } = await import('playwright');
    const exe = chromium.executablePath();
    browser = existsSync(exe);
    browserDetail = browser ? 'chromium present' : `chromium not downloaded (${exe})`;
  } catch (e) {
    browserDetail = String(e.message).split('\n')[0];
  }
}
add(browser, 'playwright chromium', browserDetail,
    `cd ${HERE} && npx playwright install chromium`);

// --- vendored client libraries --------------------------------------------
const htmx = existsSync(join(HERE, 'vendor', 'htmx.min.js'));
add(htmx, 'runtime/vendor/htmx.min.js', htmx ? 'present' : 'missing',
    'restore the vendored client libraries — they are committed, not installed');

// --- ladder config and shooter --------------------------------------------
const ladder = join(HERE, 'ladder.json');
const haveLadder = existsSync(ladder);
let rungs = '';
if (haveLadder) rungs = Object.keys(JSON.parse(readFileSync(ladder, 'utf8')).rungs).join(', ');
add(haveLadder, 'runtime/ladder.json', haveLadder ? `rungs: ${rungs}` : 'missing',
    'restore runtime/ladder.json — the viewport ladder is config, not code');
const shoot = existsSync(join(HERE, 'shoot.mjs'));
add(shoot, 'runtime/shoot.mjs', shoot ? 'present' : 'missing',
    'restore runtime/shoot.mjs — the ladder-aware screenshot pass');

// --- report ----------------------------------------------------------------
let failed = 0;
for (const r of rows) {
  if (!r.ok) failed++;
  console.log(`${r.ok ? '  ok  ' : '  MISS'} ${r.name.padEnd(28)} ${r.detail}`);
}

if (failed) {
  console.log(`\n${failed} missing. To fix:`);
  const seen = new Set();
  for (const r of rows) {
    if (!r.ok && !seen.has(r.fix)) { seen.add(r.fix); console.log(`  ${r.fix}`); }
  }
  console.log('\nThe render and console gates cannot run until these are present.');
  console.log('Do not proceed and report the design as verified — it will not be.');
  process.exit(1);
}
console.log('\nall present — render and console gates can run');
