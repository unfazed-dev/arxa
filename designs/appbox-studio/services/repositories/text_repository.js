// appbox:provenance
// generator: appbox  licence: free  project: 662368770980
// Built with appbox (free tier) — https://appbox.dev
// Text repository — routes a widget's COPY to the file that actually owns it.
//
// Layout edits have one target (the authored element, see widget_repository).
// Copy does not: the same rendered string may live in an ARB catalogue, in a
// localized design seed, or as a literal in the surface partial. Writing to the
// wrong one is silent — the studio would show the edit (its own read is
// re-prefetched) while the real source kept the old string and the next build
// reverted it. So provenance is CLASSIFIED first and stated to the user, and
// each class has its own writer.
//
// This module reads through widget_repository's /project-src/ window rather
// than re-implementing it: the same raw-source view, so an ARB's key order and
// @-metadata survive a write (a parse+re-serialise would reorder keys and drop
// the @siblings, which is exactly why the parsed /project/<rel> fixture cannot
// be the edit target).
import { readSource, resolveWidget, screensUsing, writeProjectSource } from './widget_repository.js';

// ---------------------------------------------------------------- discovery
// Both indices are fixtures because fs_shim has no readdir (worker.dart).
const idx = (name) => {
  const raw = readSource(name); // readSource() already roots at /project-src/
  try { return raw ? JSON.parse(raw) : []; } catch { return []; }
};
export const arbFiles = () => idx('l10n-index.json');
export const seedFiles = () => idx('seed-index.json');

// design/l10n/app_pl.arb -> pl ; design/models/x_model/x_seed.pl.json -> pl
const LOCALE_OF_ARB = /app_([A-Za-z0-9-]+)\.arb$/;
const LOCALE_OF_SEED = /_seed\.([A-Za-z0-9-]+)\.json$/;
export const locales = () =>
  [...new Set(arbFiles().map((arbFile) => arbFile.match(LOCALE_OF_ARB)?.[1]).filter(Boolean))];

// ------------------------------------------------------------- inner text
// elsIn() hands back the OPEN tag only. The close is found by counting nested
// same-name opens, which is sound here for the same reason the open-tag regex
// is: these are our own linted templates, and a `>` never appears bare.
const innerRange = (src, tag, openEnd) => {
  // One left-to-right pass from the open tag's end, depth-counting same-name
  // opens against closes. Self-closing `<tag/>` does not open a level. The
  // brace alternative keeps the scan sound on TSX sources, where a `>` can
  // hide inside an attribute's {…} expression (the arrow of a callback).
  const scan = new RegExp(`<${tag}(?:"[^"]*"|'[^']*'|\\{(?:[^{}]|\\{[^{}]*\\})*\\}|[^>"'])*>|</${tag}\\s*>`, 'g');
  scan.lastIndex = openEnd;
  let depth = 0;
  for (let match; (match = scan.exec(src)); ) {
    if (match[0].startsWith('</')) {
      if (depth === 0) return { start: openEnd, end: match.index };
      depth--;
    } else if (!match[0].endsWith('/>')) depth++;
  }
  return null; // unclosed — caller reports "no editable text" rather than guessing
};

// ------------------------------------------------------------- classifier
// Three provenance classes, in the order the editor must try them. Copy comes
// in two surface dialects: legacy nunjucks ({{ t('k') }}, {{ x.y }}) and TSX
// ({t('k') as string}, {x.y}) — the regexes read both.
const ARB_RE = /^\s*\{\{?\s*t\(\s*['"]([^'"]+)['"][^)]*\)\s*(?:as\s+[A-Za-z]+)?\s*\}\}?\s*$/;
const BIND_RE = /^\s*\{\{?\s*([A-Za-z_$][\w$]*(?:\.[\w$]+)*)\s*\}?\}?\s*$/;

// A t() call anywhere in the element, not only as the whole of it.
const T_CALL_RE = /\bt\(\s*['"]([^'"]+)['"]/g;

export const classify = (text) => {
  const arb = text.match(ARB_RE);
  if (arb) return { source: 'arb', key: arb[1] };

  // Most real widgets are an icon plus a label — `<Icon name="user" /> {t('k')}`.
  // Treating those as unroutable would refuse two thirds of portalo's widgets
  // while the copy sits in plain sight. If EXACTLY ONE t() key appears, that
  // key is unambiguously the element's copy and the ARB write is exact; the
  // surrounding markup is never touched. Two or more keys IS ambiguous (which
  // one did the user click?) and stays refused.
  const keys = [...new Set([...text.matchAll(T_CALL_RE)].map((match) => match[1]))];
  if (keys.length === 1) return { source: 'arb', key: keys[0], partial: true };
  if (keys.length > 1) return { source: 'mixed', keys };

  const bind = text.match(BIND_RE);
  // A binding is NOT assumed to be seed-backed: portalo's surfaces bind loop
  // variables ({next.to}, {tab.id}), never a seed path, so the seed
  // key cannot be recovered from the template. Resolving it needs the VALUE
  // the viewmodel passed, which the source window does not carry — so this
  // class is reported, not written, and the editor sends the user to the seed.
  if (bind) return { source: 'bound', expr: bind[1] };
  if (/{[{%]/.test(text)) return { source: 'mixed' };
  return { source: 'literal' };
};

// ---------------------------------------------------------------- read side
export const textProvenance = (screenId, kind, index = 0) => {
  const widget = resolveWidget(screenId, kind, index);
  if (!widget) return null;
  const src = readSource(widget.file);
  if (!src) return null;
  // The open tag's range comes FROM resolveWidget — one identity rule, so this
  // module can never select a different element than the layout editor does.
  const range = innerRange(src, widget.tag, widget.end);
  if (!range) return null;
  const text = src.slice(range.start, range.end);
  return {
    ...classify(text.trim()),
    file: widget.file, kind, index, tag: widget.tag,
    text: text.trim(),
    range: range,
    // Stated BEFORE the edit lands: one definition can feed many screens.
    // Degrades to [] rather than throwing — this is provenance COMMENTARY, and
    // a project without an intake registry (or one still being scaffolded) must
    // still be editable. The write targets above do not depend on it.
    screens: (() => { try { return screensUsing(widget.file); } catch { return []; } })(),
    locales: locales(),
  };
};

// The key's CURRENT value in one locale's PROJECT catalogue, or null when the
// project does not declare it there (it then resolves from the artifact's base
// catalogue on merge — the override case, see addArbValue). A parse is fine on
// the READ side; only writes must preserve raw key order / @-metadata.
export const arbValue = (key, locale = 'en') => {
  const rel = arbFiles().find((arbFile) => arbFile.match(LOCALE_OF_ARB)?.[1] === locale);
  if (!rel) return null;
  const raw = readSource(rel);
  if (raw == null) return null;
  try {
    const parsed = JSON.parse(raw);
    return typeof parsed[key] === 'string' ? parsed[key] : null;
  } catch {
    return null;
  }
};

// --------------------------------------------------------------- write side
// Replace one ARB value in RAW text. The key order and every @-metadata
// sibling survive because nothing is re-serialised — only the value's own
// JSON string literal is swapped, re-escaped with JSON.stringify.
export const setArbValue = (raw, key, value) => {
  const re = new RegExp(`("${key.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}"\\s*:\\s*)"(?:[^"\\\\]|\\\\.)*"`);
  if (!re.test(raw)) return null;
  return raw.replace(re, `$1${JSON.stringify(value)}`);
};

// Append a key the project catalogue does not declare yet. This is the OVERRIDE
// case, and it is legitimate rather than a fallback: worker.dart merges
// design/l10n/app_*.arb OVER the artifact's catalogue with the project winning,
// so ~11% of portalo's surface-referenced keys (app.brand, auth.continue, …)
// resolve from the base catalogue and can only be customised by adding them
// here. Kept behind an explicit flag so a typo'd key can never silently create
// a dead entry — the caller has to mean it.
export const addArbValue = (raw, key, value) => {
  const end = raw.lastIndexOf('}');
  if (end < 0) return null;
  const head = raw.slice(0, end).replace(/\s*$/, '');
  const needsComma = /[}\]"\d]$/.test(head) && !/[{[]$/.test(head);
  return `${head}${needsComma ? ',' : ''}\n  ${JSON.stringify(key)}: ${JSON.stringify(value)}\n${raw.slice(end)}`;
};

// Route + write. `locale` picks WHICH catalogue an arb edit lands in: editing
// the string you are looking at must not silently rewrite English while the
// studio renders Polish.
export const setWidgetText = async (screenId, kind, index, value, locale = 'en', opts = {}) => {
  const provenance = textProvenance(screenId, kind, index);
  if (!provenance) throw new Error(`widget not found: ${screenId} ${kind}`);

  if (provenance.source === 'arb') {
    const rel = arbFiles().find((arbFile) => arbFile.match(LOCALE_OF_ARB)?.[1] === locale);
    if (!rel) throw new Error(`no catalogue for locale ${locale} (have: ${locales().join(', ') || 'none'})`);
    const raw = readSource(rel);
    if (raw == null) throw new Error(`catalogue unreadable: ${rel}`);
    let next = setArbValue(raw, provenance.key, value);
    let override = false;
    if (next == null) {
      if (!opts.allowOverride) {
        const error = new Error(
          `"${provenance.key}" is not declared in ${rel} — it resolves from the artifact's base catalogue. ` +
          `Re-run with allowOverride to add a project override (the project wins on merge).`,
        );
        error.provenance = { ...provenance, wouldOverride: rel };
        throw error;
      }
      next = addArbValue(raw, provenance.key, value);
      override = true;
      if (next == null) throw new Error(`catalogue ${rel} is not a JSON object`);
    }
    await writeProjectSource(rel, next);
    return { ...provenance, wrote: rel, locale, override };
  }

  if (provenance.source === 'literal') {
    const src = readSource(provenance.file);
    const next = src.slice(0, provenance.range.start) + value + src.slice(provenance.range.end);
    await writeProjectSource(provenance.file, next);
    return { ...provenance, wrote: provenance.file };
  }

  // 'bound' and 'mixed' are deliberately not written: see classify().
  const err = new Error(
    provenance.source === 'bound'
      ? `"${provenance.text}" is data-bound (${provenance.expr}) — its copy lives in a design seed, not in the surface. Edit the seed: ${seedFiles().join(', ') || '(none in this project)'}`
      : `"${provenance.text}" mixes template logic with copy — split it before editing.`,
  );
  err.provenance = provenance;
  throw err;
};
