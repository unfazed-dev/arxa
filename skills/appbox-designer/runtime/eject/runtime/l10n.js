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
const esc = (unsafeText) =>
  String(unsafeText).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');

// ARB files may carry `//` comment lines — strip them before JSON.parse.
/**
 * @param {string} file
 */
const parseArb = (file) =>
  JSON.parse(
    readFileSync(file, 'utf8')
      .split('\n')
      .filter((/** @type {string} */ line) => !line.trimStart().startsWith('//'))
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
      for (const fileName of readdirSync(dir)) {
        const arbNameMatch = fileName.match(/^app_(.+)\.arb$/);
        if (!arbNameMatch) continue;
        const entries = parseArb(path.join(dir, fileName));
        catalogs[arbNameMatch[1]] = Object.fromEntries(
          Object.entries(entries).filter(([entryKey]) => !entryKey.startsWith('@')),
        );
      }
    }
  } else {
    // Workers: use preloaded ARB catalogs (runtime/preload.js).
    for (const [locale, entries] of Object.entries(artifactDirOrPreload?.arb ?? {})) {
      catalogs[locale] = Object.fromEntries(
        Object.entries(entries).filter(([entryKey]) => !entryKey.startsWith('@')),
      );
    }
  }
  const locales = Object.keys(catalogs).sort((localeA, localeB) => (localeA === 'en' ? -1 : localeB === 'en' ? 1 : localeA.localeCompare(localeB)));
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
    text.replace(/\{(\w+)\}/g, (/** @type {string} */ fullMatch, /** @type {string} */ name) => (vars && name in vars ? esc(/** @type {string} */ (vars[name])) : fullMatch));

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
      const count = Number(vars?.[plural.varName]);
      if (Number.isNaN(count)) return value;
      const picked =
        plural.options[`=${count}`] ??
        plural.options[selectPlural(locale, count)] ??
        plural.options.other;
      return picked === undefined ? value : interpolate(picked, vars);
    }
    return interpolate(value, vars);
  };

  // createTranslator({ locale, level }) → t(key, vars?). Fallback: active locale → en →
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
  let cursor = head[0].length;
  while (cursor < str.length - 1) {
    while (str[cursor] === ' ') cursor++;
    const keyword = str.slice(cursor).match(/^(=\d+|zero|one|two|few|many|other)\s*\{/);
    if (!keyword) return null;
    let depth = 1;
    let scanIndex = cursor + keyword[0].length;
    const start = scanIndex;
    while (scanIndex < str.length && depth > 0) {
      if (str[scanIndex] === '{') depth++;
      else if (str[scanIndex] === '}') depth--;
      if (depth > 0) scanIndex++;
    }
    if (depth !== 0) return null;
    options[keyword[1]] = str.slice(start, scanIndex);
    cursor = scanIndex + 1;
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
      const qualityParam = params.map((param) => param.trim()).find((param) => param.startsWith('q='));
      return { tag: tag.trim().toLowerCase(), quality: qualityParam ? Number(qualityParam.slice(2)) : 1 };
    })
    .filter((entry) => entry.tag && entry.quality > 0)
    .sort((entryA, entryB) => entryB.quality - entryA.quality)
    .map((entry) => entry.tag);
}

// Resolution precedence: ?lang= query → prefs cookie `lang` → Accept-Language
// (q-factor order, exact then base-tag match — pl-PL matches a pl catalog) → 'en'.
/**
 * @param {import('./types').Context} context
 * @param {import('./types').L10n} l10n
 * @returns {string}
 */
export function resolveLocale(context, l10n) {
  const { locales } = l10n;
  if (!locales.length) return 'en';
  const queryLang = context.req.query('lang');
  if (queryLang && locales.includes(queryLang)) return queryLang;
  const prefsLang = prefsOf(context).lang;
  if (prefsLang && locales.includes(prefsLang)) return prefsLang;
  const header = context.req.header('Accept-Language');
  if (header) {
    for (const tag of parseAcceptLanguage(header)) {
      const hit =
        locales.find((/** @type {string} */ candidate) => candidate === tag) ??
        locales.find((/** @type {string} */ candidate) => candidate === tag.split('-')[0]) ??
        locales.find((/** @type {string} */ candidate) => candidate.split('-')[0] === tag.split('-')[0]);
      if (hit) return hit;
    }
  }
  return 'en';
}

/**
 * @param {import('./types').Context} context
 * @returns {string}
 */
export const localeOf = (context) => context.get('locale') ?? 'en';
