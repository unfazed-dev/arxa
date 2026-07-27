#!/usr/bin/env node
// Wiring checks — the PRESENCE half of the gate suite.
//
//   node check_wiring.mjs <artifact-dir> <property>
//
//   fragments         every rendered Named Fragment exists as a macro
//   mutations-posted  every non-GET route is the target of a matching hx-* attribute
//   urls-resolve      every static URL in markup matches a route
//   targets-exist     every hx-target="#id" names an element that exists
//
// Everything else in this skill is a prohibition: it asserts the artifact does
// not do a banned thing. Nothing asserted the artifact DID anything, which is
// how one carrying htmx and using none of it scored a clean sweep. These four
// are joins — markup against routes, viewmodels against templates — and a join
// cannot pass vacuously when one side is empty.
import { readdirSync, readFileSync, statSync, existsSync } from 'node:fs';
import path from 'node:path';

const [dirArg, what] = process.argv.slice(2);
const PROPS = ['fragments', 'mutations-posted', 'urls-resolve', 'targets-exist'];
if (!dirArg || !PROPS.includes(what)) {
  console.error(`Usage: node check_wiring.mjs <artifact-dir> <${PROPS.join('|')}>`);
  process.exit(2);
}
const dir = path.resolve(dirArg);
const rel = (f) => path.relative(dir, f);

const walk = (d) =>
  readdirSync(d).flatMap((f) => {
    const p = path.join(d, f);
    return statSync(p).isDirectory() ? walk(p) : [p];
  });

// Same rule as the linter: comments are not behaviour, in either direction. A
// commented-out hx-post must not satisfy "this route is reachable".
const uncommented = (s) =>
  s.replace(/<!--[\s\S]*?-->/g, '').replace(/\{#[\s\S]*?#\}/g, '');

const files = walk(dir);
const markup = files
  .filter((f) => f.endsWith('.html'))
  .map((f) => [f, uncommented(readFileSync(f, 'utf8'))]);

const routesFile = path.join(dir, 'app.routes.js');
const routes = [
  ...readFileSync(routesFile, 'utf8').matchAll(
    /\[\s*'(GET|POST|PUT|PATCH|DELETE)'\s*,\s*'([^']+)'/g,
  ),
].map((m) => ({ method: m[1], path: m[2] }));

const problems = [];
const bad = (msg) => problems.push(msg);

if (what === 'fragments') {
  for (const f of files.filter((f) => f.endsWith('_viewmodel.js'))) {
    const src = readFileSync(f, 'utf8');
    // `const VIEW = '…'` when the file names its template once and builds
    // fragment paths from it; otherwise the co-located view, which is the
    // artifact convention.
    const named = src.match(/const VIEW\s*=\s*['"]([^'"]+)['"]/);
    const view = named
      ? path.join(dir, named[1])
      : f.replace(/_viewmodel\.js$/, '_view.html');
    const wanted = new Set(
      [...src.matchAll(/[`'"][^`'"]*#(\w+)[`'"]/g)].map((m) => m[1]),
    );
    if (!wanted.size) continue;
    if (!existsSync(view)) {
      bad(`${rel(f)}: renders a fragment, but ${rel(view)} does not exist`);
      continue;
    }
    const tpl = readFileSync(view, 'utf8');
    for (const n of wanted) {
      if (!new RegExp(`\\{%-?\\s*macro\\s+${n}\\s*\\(`).test(tpl)) {
        bad(`${rel(f)}: renders "#${n}", but ${rel(view)} defines no such macro`);
      }
    }
  }
}

if (what === 'mutations-posted') {
  const sent = new Set();
  for (const [, t] of markup) {
    for (const m of t.matchAll(/hx-(get|post|put|patch|delete)\s*=\s*"([^"{]+)"/gi)) {
      sent.add(`${m[1].toUpperCase()} ${m[2].split('?')[0]}`);
    }
  }
  for (const r of routes) {
    if (r.method === 'GET') continue; // a GET is reachable by boosted link or address bar
    if (!sent.has(`${r.method} ${r.path}`)) {
      bad(
        `${r.method} ${r.path} is a route no markup sends to — it is either dead, ` +
          `or reached by a plain form, which is how htmx ends up carried and unused`,
      );
    }
  }
}

if (what === 'urls-resolve') {
  const known = new Set(routes.map((r) => r.path));
  for (const [f, t] of markup) {
    // `[^"{]` skips anything templated — `href="{{ u.href }}"` is built from
    // context this cannot see, and guessing at it would only add noise.
    for (const m of t.matchAll(
      /(?:hx-(?:get|post|put|patch|delete)|href)\s*=\s*"(\/[^"{]*)"/gi,
    )) {
      const u = m[1].split('?')[0].split('#')[0];
      if (u.startsWith('/assets/') || u.startsWith('/_ds/')) continue;
      if (!known.has(u)) bad(`${rel(f)}: "${u}" matches no route in app.routes.js`);
    }
  }
}

if (what === 'targets-exist') {
  const ids = new Set();
  for (const [, t] of markup) {
    for (const m of t.matchAll(/\bid\s*=\s*"([^"{]+)"/g)) ids.add(m[1]);
  }
  for (const [f, t] of markup) {
    // Only `#id` targets. `closest tr`, `this`, `next` and friends are
    // relative and resolve at runtime — nothing static to join them against.
    for (const m of t.matchAll(/hx-target\s*=\s*"#([^"\s]+)"/g)) {
      if (!ids.has(m[1])) {
        bad(`${rel(f)}: hx-target="#${m[1]}" — no element in the artifact carries that id`);
      }
    }
  }
}

if (problems.length) {
  console.error(problems.join('\n'));
  process.exit(1);
}
console.log(`${what}: ok`);
