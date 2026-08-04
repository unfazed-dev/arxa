// appbox:provenance
// generator: appbox  licence: free  project: 662368770980
// Built with appbox (free tier) — https://appbox.dev
// Widget repository — SOURCE truth for the widget manager. The rendered DOM
// (explode.js's territory) is the only place resolved names exist, but edits
// target the DEFINITION: the authored element in the project's surface
// partials. The static `data-el` KIND prefix ("card:", "tab:") survives
// templating, so identity here is (file, kind, occurrence) — a loop rendering
// four cards from one source element is still ONE definition, which is what
// makes "edit once, every screen follows" true rather than aspirational.
//
// Sources arrive via the worker's /project-src/ prefetch (see _scanArtifact in
// appboxd/lib/design_server/worker.dart): fs_shim has no readdir, so
// project-src/index.json lists the files. Writes go through /__project_write
// (same channel as fixtures) and update the prefetched key immediately; the
// project watcher re-prefetches for everyone else ~200ms later.
import { existsSync, readFileSync } from 'node:fs';
import { registry } from './project_repository.js';

const srcUrl = (rel) => new URL(`../../project-src/${rel}`, import.meta.url);

export const surfaceFiles = () =>
  existsSync(srcUrl('index.json')) ? JSON.parse(readFileSync(srcUrl('index.json'), 'utf8')) : [];

export const readSource = (rel) =>
  existsSync(srcUrl(rel)) ? readFileSync(srcUrl(rel), 'utf8') : null;

// portalo.home -> design/surfaces/home.html (the live-read layout contract)
export const screenFile = (screenId) =>
  `design/surfaces/${String(screenId).split('.').pop()}.html`;

const INCLUDE_RE = /{%\s*include\s+"ui\/project\/([^"]+)"\s*%}/g;
export const includesOf = (rel) => {
  const src = readSource(rel);
  if (!src) return [];
  return [...src.matchAll(INCLUDE_RE)].map((m) => `design/surfaces/${m[1]}`);
};

// Every open tag carrying data-el, in source order. Nunjucks-templated HTML is
// not strictly parseable as HTML, but an OPEN TAG is: attributes may contain
// {{ }} but never a bare `>` (the templates are ours and linted).
const TAG_RE = /<([a-zA-Z][\w-]*)((?:"[^"]*"|'[^']*'|[^>"'])*)>/g;
const elsIn = (src) => {
  const out = [];
  for (const m of src.matchAll(TAG_RE)) {
    const attrs = m[2];
    const el = attrs.match(/data-el="([^":]+)(:|")/);
    if (el) out.push({ tag: m[1], attrs, kind: el[1], start: m.index, end: m.index + m[0].length });
  }
  return out;
};

const LAYOUT_ATTRS = ['data-layout', 'data-flow', 'data-wrap', 'data-clip', 'data-gap', 'data-pad', 'data-resize-x', 'data-resize-y'];
const attrsOf = (attrString) => {
  const out = {};
  for (const a of LAYOUT_ATTRS) {
    const m = attrString.match(new RegExp(`${a}(?:="([^"]*)")?(?=[\\s>/]|$)`));
    if (m) out[a] = m[1] ?? '';
  }
  return out;
};

// Resolve a widget definition for (screen, kind): the screen's own file first,
// then its included partials — deterministic, mirroring how the render composes.
// index picks among multiple same-kind SOURCE elements in one file (rare;
// explode.js posts 0 today — ponytail: per-DOM-node disambiguation lands with
// the canvas handles increment, where geometry identifies the node).
export const resolveWidget = (screenId, kind, index = 0) => {
  const own = screenFile(screenId);
  for (const rel of [own, ...includesOf(own)]) {
    const src = readSource(rel);
    if (!src) continue;
    const hits = elsIn(src).filter((e) => e.kind === kind);
    if (hits.length > index) {
      const e = hits[index];
      // start/end of the OPEN TAG ride along so no caller has to re-derive
      // element identity with a second, subtly different rule. elsIn() counts
      // occurrences of a kind across EVERY tag name and delimits the kind with
      // `:` or `"` — a re-find that scanned only `<${tag}` would disagree the
      // moment one kind appears on two different tags, and a prefix match
      // would let kind "tab" select a "tabbar:" element.
      return { file: rel, kind, index, tag: e.tag, attrs: attrsOf(e.attrs), start: e.start, end: e.end };
    }
  }
  return null;
};

// Every widget ADDRESSABLE on a screen, enumerated with the exact rule
// resolveWidget applies — (kind, i) for i = 0.. until resolution fails. This
// mirrors rather than re-derives: a per-file listing would disagree with
// resolveWidget the moment one kind appears in both the screen's own file and
// an include (the per-file index rule can shadow an include's earlier
// occurrence), and the Tools strip must only ever offer selections the editor
// can actually resolve.
export const widgetsOn = (screenId) => {
  const own = screenFile(screenId);
  const kinds = [];
  for (const rel of [own, ...includesOf(own)]) {
    const src = readSource(rel);
    if (!src) continue;
    for (const e of elsIn(src)) if (!kinds.includes(e.kind)) kinds.push(e.kind);
  }
  const out = [];
  for (const kind of kinds) {
    for (let i = 0; ; i++) {
      const w = resolveWidget(screenId, kind, i);
      if (!w) break;
      out.push({ kind, index: i, tag: w.tag, file: w.file });
    }
  }
  return out;
};

// Screens whose render includes this file — the "applies to N screens"
// provenance the editor must state before an edit lands.
export const screensUsing = (rel) =>
  (registry() ?? [])
    .filter((s) => {
      const own = screenFile(s.id);
      return own === rel || includesOf(own).includes(rel);
    })
    .map((s) => s.id);

// Set/replace/remove one attribute on the widget's source element and write
// the file back through the project channel. value '' removes the attribute.
export const setWidgetAttr = async (screenId, kind, index, attr, value) => {
  const w = resolveWidget(screenId, kind, index);
  if (!w) throw new Error(`widget not found: ${screenId} ${kind}`);
  const src = readSource(w.file);
  const hits = elsIn(src).filter((e) => e.kind === kind);
  const e = hits[index];
  let open = src.slice(e.start, e.end);
  const re = new RegExp(`\\s*${attr}(?:="[^"]*")?(?=[\\s>/])`);
  if (re.test(open)) open = open.replace(re, value === '' ? '' : ` ${attr}="${value}"`);
  else if (value !== '') open = open.replace(/(\s*\/?>)$/, ` ${attr}="${value}"$1`);
  const next = src.slice(0, e.start) + open + src.slice(e.end);
  await writeProjectSource(w.file, next);
  return resolveWidget(screenId, kind, index);
};

// Same channel + same immediate-visibility contract as writeProjectFixture,
// keyed for /project-src/ (the worker template map catches up on the watcher
// re-prefetch — that is what re-renders every OPEN stub, so cross-screen sync
// is the watcher's job, not this function's).
export const writeProjectSource = async (rel, body) => {
  const origin = new URL('../../', import.meta.url).href.replace(/\/$/, '');
  const res = await fetch(`${origin}/__project_write`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ path: rel, body }),
  });
  if (!res.ok) throw new Error(`project write failed (${res.status}): ${await res.text()}`);
  globalThis.__fixtures[`${origin}/project-src/${rel}`] = body;
};
