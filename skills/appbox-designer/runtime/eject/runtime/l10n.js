// @ts-check
// L10n — artifact string catalogs, locale resolution, and the t() translator.
//
// Catalogs live at <artifact>/l10n/app_<locale>.arb — plain JSON, `//` comment
// lines allowed (ARB tooling emits them), `@`-prefixed metadata keys ignored.
// An artifact with no l10n/ dir gets a pass-through t() and locale 'en':
// nothing about the pre-i18n contract changes.
import { existsSync, readFileSync, readdirSync } from 'node:fs';
import path from 'node:path';
import { prefsOf } from './state.js';

/**
 * @param {string} s
 * @returns {string}
 */
const esc = (s) =>
  String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');

// ARB files may carry `//` comment lines — strip them before JSON.parse.
/**
 * @param {string} file
 */
const parseArb = (file) =>
  JSON.parse(
    readFileSync(file, 'utf8')
      .split('\n')
      .filter((/** @type {string} */ l) => !l.trimStart().startsWith('//'))
      .join('\n'),
  );

/**
 * @param {any} artifactDirOrPreload
 * @returns {import('./types').L10n}
 */
export function createL10n(artifactDirOrPreload) {
  /** @type {Record<string, Record<string, string>>} */
  const catalogs = {};
  if (typeof artifactDirOrPreload === 'string') {
    // node: read ARB catalogs from the filesystem.
    const dir = path.join(artifactDirOrPreload, 'l10n');
    if (existsSync(dir)) {
      for (const f of readdirSync(dir)) {
        const m = f.match(/^app_(.+)\.arb$/);
        if (!m) continue;
        const entries = parseArb(path.join(dir, f));
        catalogs[m[1]] = Object.fromEntries(
          Object.entries(entries).filter(([k]) => !k.startsWith('@')),
        );
      }
    }
  } else {
    // Workers: use preloaded ARB catalogs (runtime/preload.js).
    for (const [locale, entries] of Object.entries(artifactDirOrPreload?.arb ?? {})) {
      catalogs[locale] = Object.fromEntries(
        Object.entries(entries).filter(([k]) => !k.startsWith('@')),
      );
    }
  }
  const locales = Object.keys(catalogs).sort((a, b) => (a === 'en' ? -1 : b === 'en' ? 1 : a.localeCompare(b)));
  const pluralRules = new Map(); // locale → Intl.PluralRules, built once

  /**
   * @param {string} locale
   * @param {number} n
   * @returns {string}
   */
  const selectPlural = (locale, n) => {
    if (!pluralRules.has(locale)) pluralRules.set(locale, new Intl.PluralRules(locale));
    return pluralRules.get(locale).select(n);
  };

  // ICU subset by design: plural + {var} only (known ceiling) — swap in
  // intl-messageformat if select/nested cases ever appear.
  /**
   * @param {string} text
   * @param {Record<string, unknown> | undefined} vars
   * @returns {string}
   */
  const interpolate = (text, vars) =>
    text.replace(/\{(\w+)\}/g, (/** @type {string} */ m, /** @type {string} */ name) => (vars && name in vars ? esc(/** @type {string} */ (vars[name])) : m));

  /**
   * @param {Record<string, string>} catalog
   * @param {string} locale
   * @param {string} key
   * @param {Record<string, unknown> | undefined} vars
   * @returns {string | undefined}
   */
  const translate = (catalog, locale, key, vars) => {
    let value = catalog[key];
    if (typeof value !== 'string') return undefined;
    const plural = parsePlural(value);
    if (plural) {
      const n = Number(vars?.[plural.varName]);
      if (Number.isNaN(n)) return value;
      const picked =
        plural.options[`=${n}`] ??
        plural.options[selectPlural(locale, n)] ??
        plural.options.other;
      return picked === undefined ? value : interpolate(picked, vars);
    }
    return interpolate(value, vars);
  };

  // createT({ locale, level }) → t(key, vars?). Fallback: active locale → en →
  // the key literal. level 'plain'|'technical' tries key+Plain / key+Technical
  // first, then the base key (base = balanced). Returns a plain string:
  // catalog text is authored (trusted), interpolated vars are HTML-escaped in
  // interpolate(). The TSX renderer wraps t() in raw() to prevent double-escaping.
  const createT = (/** @type {{ locale?: string, level?: string }} */ { locale = 'en', level } = {}) => {
    const cat = catalogs[locale] ?? {};
    const en = catalogs.en ?? {};
    return (/** @type {string} */ key, /** @type {Record<string, unknown> | undefined} */ vars) => {
      const variants =
        level === 'plain' ? [key + 'Plain', key]
        : level === 'technical' ? [key + 'Technical', key]
        : [key];
      for (const k of variants) {
        const hit = translate(cat, locale, k, vars) ?? translate(en, 'en', k, vars);
        if (hit !== undefined) return hit;
      }
      return key;
    };
  };

  return { catalogs, locales, createT };
}

// `{count, plural, =0{…} one{…} few{…} many{…} other{…}}` → { varName, options }.
// Option bodies may nest one level of `{var}` placeholders — braces are
// balanced by walking, not by regex. Returns null for non-plural values.
// Exported for runtime/pseudolocalize.mjs, which rewrites option bodies.
/**
 * @param {string} str
 * @returns {{ varName: string, options: Record<string, string | undefined> } | null}
 */
export function parsePlural(str) {
  const head = str.match(/^\{\s*(\w+)\s*,\s*plural\s*,\s*/);
  if (!head || !str.endsWith('}')) return null;
  /** @type {Record<string, string | undefined>} */
  const options = {};
  let i = head[0].length;
  while (i < str.length - 1) {
    while (str[i] === ' ') i++;
    const kw = str.slice(i).match(/^(=\d+|zero|one|two|few|many|other)\s*\{/);
    if (!kw) return null;
    let depth = 1;
    let j = i + kw[0].length;
    const start = j;
    while (j < str.length && depth > 0) {
      if (str[j] === '{') depth++;
      else if (str[j] === '}') depth--;
      if (depth > 0) j++;
    }
    if (depth !== 0) return null;
    options[kw[1]] = str.slice(start, j);
    i = j + 1;
  }
  return { varName: head[1], options };
}

// Parse `Accept-Language: pl-PL,pl;q=0.9,en;q=0.8` → ['pl-pl', 'pl', 'en'],
// highest q first. q=0 means "not acceptable" — dropped.
/**
 * @param {string} header
 * @returns {string[]}
 */
export function parseAcceptLanguage(header) {
  return String(header)
    .split(',')
    .map((part) => {
      const [tag, ...params] = part.trim().split(';');
      const q = params.map((p) => p.trim()).find((p) => p.startsWith('q='));
      return { tag: tag.trim().toLowerCase(), q: q ? Number(q.slice(2)) : 1 };
    })
    .filter((e) => e.tag && e.q > 0)
    .sort((a, b) => b.q - a.q)
    .map((e) => e.tag);
}

// Resolution precedence: ?lang= query → prefs cookie `lang` → Accept-Language
// (q-factor order, exact then base-tag match — pl-PL matches a pl catalog) → 'en'.
/**
 * @param {import('./types').Context} c
 * @param {import('./types').L10n} l10n
 * @returns {string}
 */
export function resolveLocale(c, l10n) {
  const { locales } = l10n;
  if (!locales.length) return 'en';
  const q = c.req.query('lang');
  if (q && locales.includes(q)) return q;
  const p = prefsOf(c).lang;
  if (p && locales.includes(p)) return p;
  const header = c.req.header('Accept-Language');
  if (header) {
    for (const tag of parseAcceptLanguage(header)) {
      const hit =
        locales.find((/** @type {string} */ l) => l === tag) ??
        locales.find((/** @type {string} */ l) => l === tag.split('-')[0]) ??
        locales.find((/** @type {string} */ l) => l.split('-')[0] === tag.split('-')[0]);
      if (hit) return hit;
    }
  }
  return 'en';
}

/**
 * @param {import('./types').Context} c
 * @returns {string}
 */
export const localeOf = (c) => c.get('locale') ?? 'en';
