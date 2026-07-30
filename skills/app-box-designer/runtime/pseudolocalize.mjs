#!/usr/bin/env node
// Pseudolocalize — generate the qps-ploc pseudo-locale from the English SSOT.
//
//   node runtime/pseudolocalize.mjs <artifact-dir>
//
// Reads <artifact>/l10n/app_en.arb → writes l10n/app_qps-ploc.arb, and each
// models/<domain>_model/<name>_seed.en.json → <name>_seed.qps-ploc.json.
// Every app_<locale>.arb on disk is an available locale, so writing the file
// IS the registration. Regenerate fixtures afterwards (the artifact's
// models/*\/generate.mjs) so the ploc seed reaches the model layer.
//
// The transform: wrap in [!! … !!], map ASCII letters to accented lookalikes,
// pad ~35% — readable-but-expanded, so truncation and hardcoded strings show
// up in review. `{var}` placeholders and ICU plural structure are preserved.
import { existsSync, readdirSync, readFileSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { parsePlural } from './lib/l10n.mjs';

const dir = process.argv[2] ? path.resolve(process.argv[2]) : null;
if (!dir) {
  console.error('Usage: node pseudolocalize.mjs <artifact-dir>');
  process.exit(64);
}

const LOOK = {
  a: 'å', e: 'ë', i: 'ï', o: 'ö', u: 'ü', y: 'ÿ',
  A: 'Å', E: 'Ë', I: 'Ï', O: 'Ö', U: 'Ü', Y: 'Ÿ',
  c: 'ç', n: 'ñ', s: 'š', z: 'ž', l: 'ł', r: 'ř', t: 'ţ', d: 'ð',
  C: 'Ç', N: 'Ñ', S: 'Š', Z: 'Ž', L: 'Ł', R: 'Ř', T: 'Ţ', D: 'Ð',
};

const expand = (text) => {
  const mapped = text.replace(/[a-zA-Z]/g, (ch) => LOOK[ch] ?? ch);
  const pad = '~̷~'.repeat(Math.max(2, Math.ceil((text.length * 0.35) / 3)));
  return `[!! ${mapped} ${pad} !!]`;
};

// Transform text, preserving {var} placeholders byte-for-byte.
function plocText(s) {
  const ph = [];
  const stripped = s.replace(/\{[^{}]+\}/g, (m) => {
    ph.push(m);
    return `\x00${ph.length - 1}\x00`;
  });
  return expand(stripped).replace(/\x00(\d+)\x00/g, (_, i) => ph[+i]);
}

// Plural values: transform each option body, keep keywords and braces.
function plocValue(v) {
  if (typeof v !== 'string') return v;
  const plural = parsePlural(v);
  if (!plural) return plocText(v);
  const body = Object.entries(plural.options)
    .map(([kw, text]) => `${kw}{${plocText(text)}}`)
    .join(' ');
  return `{${plural.varName}, plural, ${body}}`;
}

const parseArb = (file) =>
  JSON.parse(
    readFileSync(file, 'utf8')
      .split('\n')
      .filter((l) => !l.trimStart().startsWith('//'))
      .join('\n'),
  );

let wrote = 0;

// --- l10n/app_en.arb → l10n/app_qps-ploc.arb --------------------------------
const enArb = path.join(dir, 'l10n', 'app_en.arb');
if (existsSync(enArb)) {
  const src = parseArb(enArb);
  const out = {};
  for (const [k, v] of Object.entries(src)) {
    out[k] = k.startsWith('@') ? v : plocValue(v);
  }
  out['@@locale'] = 'qps-ploc'; // after the loop: en's @@locale must not win
  const target = path.join(dir, 'l10n', 'app_qps-ploc.arb');
  writeFileSync(target, JSON.stringify(out, null, 2) + '\n');
  console.log(`wrote ${path.relative(dir, target)} (${Object.keys(src).length} keys)`);
  wrote++;
} else {
  console.log(`no l10n/app_en.arb — nothing to pseudolocalize there`);
}

// --- per-locale seeds → seed.qps-ploc.json -----------------------------------
// IDs, _-prefixed metadata, and enum-typed fields stay byte-identical: the
// ploc seed must hold the same schema and joins as the en seed, only the
// human text expands. ENUM_KEYS are identifier fields templates compose into
// catalog keys (t('status.name.' ~ s.status)) or CSS classes (st-{{ s.status }})
// — wrapping them breaks the lookup and paints the key literal on screen.
const ENUM_KEYS = new Set(['id', 'status', 'state', 'severity', 'stage', 'priority', 'kind', 'tone', 'badge', 'from']);
const plocSeed = (value, key) => {
  if (typeof value === 'string') return ENUM_KEYS.has(key) || key.startsWith('_') ? value : plocText(value);
  if (Array.isArray(value)) return value.map((v) => plocSeed(v, key));
  if (value && typeof value === 'object') {
    return Object.fromEntries(Object.entries(value).map(([k, v]) => [k, plocSeed(v, k)]));
  }
  return value;
};

const modelsDir = path.join(dir, 'models');
if (existsSync(modelsDir)) {
  for (const model of readdirSync(modelsDir)) {
    const mDir = path.join(modelsDir, model);
    for (const f of readdirSync(mDir).filter((f) => /_seed\.en\.json$/.test(f))) {
      const seed = JSON.parse(readFileSync(path.join(mDir, f), 'utf8'));
      const target = path.join(mDir, f.replace(/_seed\.en\.json$/, '_seed.qps-ploc.json'));
      writeFileSync(target, JSON.stringify(plocSeed(seed, ''), null, 2) + '\n');
      console.log(`wrote ${path.relative(dir, target)} — regenerate fixtures to emit it`);
      wrote++;
    }
  }
}

if (!wrote) {
  console.error('nothing pseudolocalized — no l10n/app_en.arb and no *_seed.en.json found');
  process.exit(66);
}
