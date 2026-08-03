#!/usr/bin/env node
/**
 * composer-action integrity checker — v2.
 *
 * v1 WAS WRONG AND IS WITHDRAWN. It tested key *presence* per facade:
 *     hits = facade.match(/composerAction/g).length;  ok = hits > 0
 * That predicate is inverted on both members of its own population:
 *     scaffold_facade.js:205  declares '/scaffold/messages', UNROUTED, live 404 -> PASSED
 *     scaffold_run_facade.js  declares nothing, correct by contract             -> FAILED
 * It green-lit the only real defect and flagged the only correct file.
 * Blocking review by run-screen; replacement predicate supplied by picker-screen.
 * Worse: v1's green state for an actionless facade was reachable only by adding
 * a key without a route — i.e. by committing the exact defect class it existed
 * to catch, captioned "fix lint".
 *
 * v2 PREDICATE (picker-screen): the discriminating variable is not a per-facade
 * property at all. It is the JOIN between the declared action string and the
 * route table. A declared action that no POST route serves is a live 404.
 *
 * SCOPE CONTROL — why this re-derives the route table by content search rather
 * than by filename or directory. My own first cut of this join walked `ui/` and
 * matched /^app\.routes\.js$|^routes\..*\.js$/. It found four route files and
 * missed `app.routes.js`, which sits at the design ROOT, not under ui/. Result:
 * build_facade.js:457 and :527 reported UNROUTED. They are routed, at
 * app.routes.js:41. Two false alarms on live endpoints.
 *
 * The aggregate positive control did not catch it: three declarations resolved,
 * so the instrument "produced hits" and looked alive. But all three came from
 * files the walk had already found. A control drawn from the same source as the
 * finding cannot detect a missing source. Hence ANCHORS below: specific
 * endpoints, independently measured live by other agents, deliberately spanning
 * DIFFERENT route files. If an anchor fails, scope is wrong and no verdict is
 * emitted.
 */
const fs = require('fs');
const path = require('path');

const ROOT = process.argv[2] || path.join(__dirname, '../../designs/appbox-studio');

// Endpoints independently measured live by teammates, deliberately spanning
// separate route files so a missing file breaks an anchor rather than hiding.
const ANCHORS = [
  { p: '/build/messages',       why: 'measured live; lives in app.routes.js (design root)' },
  { p: '/design/chat/messages', why: 'lives in routes.design.js (per-shell file)' },
];

function walkJs(dir, out = []) {
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    if (e.name === 'node_modules' || e.name.startsWith('.')) continue;
    const p = path.join(dir, e.name);
    if (e.isDirectory()) walkJs(p, out);
    else if (e.name.endsWith('.js')) out.push(p);
  }
  return out;
}

// --- route table, by content over the WHOLE tree (no filename assumption) ---
const routes = [];
for (const f of walkJs(ROOT)) {
  const t = fs.readFileSync(f, 'utf8');
  for (const m of t.matchAll(/\[\s*['"](GET|POST|PUT|DELETE)['"]\s*,\s*['"]([^'"]+)['"]/g)) {
    routes.push({ method: m[1], p: m[2], file: path.relative(ROOT, f) });
  }
}
const posts = new Map();
for (const r of routes) if (r.method === 'POST') posts.set(r.p, r.file);

// --- SCOPE CONTROL: anchors must resolve, and from >1 distinct file ---
const anchorFiles = new Set();
const bad = [];
for (const a of ANCHORS) {
  const f = posts.get(a.p);
  if (!f) bad.push(a); else anchorFiles.add(f);
}
if (bad.length) {
  console.error('BLIND: scope control failed. Known-live endpoints did not resolve:');
  for (const a of bad) console.error(`  ${a.p}  — ${a.why}`);
  console.error('Route table is incomplete; refusing to emit a verdict.');
  process.exit(2);
}
if (anchorFiles.size < 2) {
  console.error(`BLIND: anchors all resolved from ${anchorFiles.size} file(s). A control cannot`);
  console.error('span sources it never read. Refusing to emit a verdict.');
  process.exit(2);
}

// --- declared composer actions ---
const fdir = path.join(ROOT, 'services/facades');
const decls = [];
for (const f of fs.readdirSync(fdir).filter(x => x.endsWith('.js'))) {
  fs.readFileSync(path.join(fdir, f), 'utf8').split('\n').forEach((ln, i) => {
    if (/^\s*(\/\/|\*)/.test(ln)) return;           // comments are not declarations
    const lit = ln.match(/composerAction\s*:\s*['"]([^'"]+)['"]/);
    const tpl = ln.match(/composerAction\s*:\s*`([^`]*)`/);
    const nul = ln.match(/composerAction\s*:\s*null/);
    if (lit)      decls.push({ f, line: i + 1, p: lit[1], kind: 'literal' });
    else if (tpl) decls.push({ f, line: i + 1, p: tpl[1], kind: 'template' });
    else if (nul) decls.push({ f, line: i + 1, p: null,   kind: 'null' });
  });
}

console.log(`route table: ${routes.length} routes (${posts.size} POST) from ${new Set(routes.map(r => r.file)).size} file(s)`);
console.log(`scope control: ${ANCHORS.length}/${ANCHORS.length} anchors resolved across ${anchorFiles.size} files\n`);

let fail = 0, unresolved = 0;
for (const d of decls) {
  const tag = (d.f + ':' + d.line).padEnd(32);
  if (d.kind === 'null') {
    console.log(`  ${tag}${'(null)'.padEnd(26)}declared actionless — pass`);
  } else if (d.kind === 'template') {
    unresolved++;
    console.log(`  ${tag}${d.p.padEnd(26)}UNRESOLVED (template literal — needs render-side confirmation, NOT a pass)`);
  } else if (!posts.has(d.p)) {
    fail++;
    console.log(`  ${tag}${d.p.padEnd(26)}*** UNROUTED — declared, no POST route, renders a live 404 ***`);
  } else {
    console.log(`  ${tag}${d.p.padEnd(26)}routed (${posts.get(d.p)})`);
  }
}

// --- advisory: gated mounts whose facade declares nothing ---
// NOT scored. Absence is overloaded: it means both "this surface has no
// mutation" (scaffold.run — correct) and "the author forgot" (a real
// regression the guard at _shared.html:75 would silence). Nothing can separate
// them from source until `composerAction: null` is adopted as the explicit
// actionless declaration. Reported so the ambiguity stays visible, not scored —
// scoring it is precisely what made v1 flag the one correct file.
const gatedFacades = ['scaffold_facade.js', 'scaffold_run_facade.js'];
const undeclared = gatedFacades.filter(g => !decls.some(d => d.f === g));
if (undeclared.length) {
  console.log('\nadvisory (not scored) — gated mount, no composerAction declared:');
  for (const u of undeclared) console.log(`  ${u} — cannot distinguish "no mutation surface" from "author forgot"`);
  console.log('  adopt `composerAction: null` to make this decidable.');
}

console.log(`\n${fail} failure(s), ${unresolved} unresolved`);
process.exit(fail ? 1 : 0);
