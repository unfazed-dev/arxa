#!/usr/bin/env node
// Zero-custom-client-JS lint (ADR-0002). Usage: node lint.mjs <artifact-dir>
// Scans artifact templates; viewmodels (.js) are server code and not in scope.
import { readdirSync, readFileSync, statSync } from 'node:fs';
import path from 'node:path';

const dir = process.argv[2] ? path.resolve(process.argv[2]) : null;
if (!dir) {
  console.error('Usage: node lint.mjs <artifact-dir>');
  process.exit(2);
}

const rules = [
  // Inert JSON data blocks (e.g. inert data) are data, not custom JS.
  { re: /<script(?![^>]*src="\/assets\/vendor\/)(?![^>]*type="application\/json")[^>]*>/i, msg: 'non-vendor <script> tag' },
  { re: /\bhx-on[:\s=]/i, msg: 'hx-on handler' },
  // Both quote styles. These matched only `"…` until an artifact wrote its
  // hx-vals JSON in single quotes — legal HTML, and necessary when the value
  // contains double quotes. `hx-vals='js:…'` would then have walked straight
  // past a ban that reads as absolute.
  { re: /\bhx-(vals|headers)\s*=\s*['"]js:/i, msg: 'js:-prefixed attribute' },
  { re: /\bhx-trigger\s*=\s*['"][^'"]*\[/i, msg: '[expr] trigger filter' },
];

const walk = (d) =>
  readdirSync(d).flatMap((f) => {
    const p = path.join(d, f);
    return statSync(p).isDirectory() ? walk(p) : [p];
  });

// Comments are not shipped behaviour. Every rule above is a pure selector —
// none of them reads an opt-out marker — so stripping comments before matching
// costs nothing and closes a real hole in both directions: a Nunjucks comment
// explaining WHY `hx-on:` is banned used to FAIL the artifact that obeyed the
// ban (documenting a rule must not be able to break the build), and a
// commented-out <script> is not a script.
const uncommented = (s) =>
  s.replace(/<!--[\s\S]*?-->/g, '').replace(/\{#[\s\S]*?#\}/g, '');

const findings = [];
for (const file of walk(dir).filter((f) => f.endsWith('.html'))) {
  const text = uncommented(readFileSync(file, 'utf8'));
  for (const { re, msg } of rules) {
    if (re.test(text)) findings.push(`${file}: ${msg}`);
  }
}

if (findings.length) {
  console.error(`client-JS lint failed:\n${findings.join('\n')}`);
  process.exit(1);
}
console.log(`lint clean: no custom client-side JS in ${dir}`);
