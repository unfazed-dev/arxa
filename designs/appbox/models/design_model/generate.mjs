// appbox:provenance
// generator: app-box  licence: free  project: 662368770980
// Built with app-box (free tier) — https://appbox.dev
// Fixture generator — design_seed.<locale>.json → run.<locale>.json (+
// run.json as the en alias). The fixture is the denormalized projection a
// template wants: shot ids minted per rung, per-rung layout notes per wire
// kind, the epic filter list, summary counts.
// Never hand-edit run*.json fixtures; edit the seed and re-run: node generate.mjs
import { readFileSync, readdirSync, writeFileSync } from 'node:fs';

const dir = new URL('.', import.meta.url);
const seeds = readdirSync(dir).filter((f) => /^design_seed\..+\.json$/.test(f));
if (!seeds.length) {
  console.error('no design_seed.<locale>.json found');
  process.exit(66);
}

// What the layout does at each rung, per wire kind — the "literal parity"
// story told in one line per shot. Generator-side copy, per locale (locales
// without their own table fall back to en).
const RUNG_NOTES = {
  en: {
    split: {
      compact: 'stacked — canvas first, rail floats below',
      medium: 'narrow 300px rail beside the canvas',
      expanded: '340px rail + one artifact large',
    },
    stack: {
      compact: 'single column, actions inline',
      medium: 'single column, wider measure',
      expanded: 'centred column, 56rem cap',
    },
    grid: {
      compact: 'one-up cards',
      medium: 'two-up grid',
      expanded: 'three-up grid',
    },
  },
  pl: {
    split: {
      compact: 'składane — najpierw kanwa, szyna unosi się poniżej',
      medium: 'wąska szyna 300px obok kanwy',
      expanded: 'szyna 340px + jeden duży artefakt',
    },
    stack: {
      compact: 'jedna kolumna, akcje w linii',
      medium: 'jedna kolumna, szersza miara',
      expanded: 'wyśrodkowana kolumna, limit 56rem',
    },
    grid: {
      compact: 'karty pojedynczo',
      medium: 'siatka podwójna',
      expanded: 'siatka potrójna',
    },
  },
};

// kimitail: fake-but-stable shot ids, good enough for a prototype fixture.
const shortHash = (s) => {
  let h = 0;
  for (const ch of s) h = (h * 31 + ch.charCodeAt(0)) >>> 0;
  return h.toString(16).padStart(8, '0');
};

for (const f of seeds.sort()) {
  const locale = f.match(/^design_seed\.(.+)\.json$/)[1];
  const seed = JSON.parse(readFileSync(new URL(f, import.meta.url), 'utf8'));
  const notes = RUNG_NOTES[locale] ?? RUNG_NOTES.en;

  const screens = seed.screens.map((s) => ({
    ...s,
    rungs: s.rungs.map((r) => ({
      ...r,
      shot: `sh_${shortHash(s.id + r.rung).slice(0, 4)}…${shortHash(r.rung + s.id).slice(0, 4)}`,
      note: notes[s.wire]?.[r.rung] ?? '',
    })),
  }));

  const fixture = {
    ...seed,
    screens,
    epics: [...new Set(screens.map((s) => s.epic))],
    counts: {
      screens: screens.length,
      shots: screens.reduce((n, s) => n + s.rungs.length, 0),
      frozen: screens.filter((s) => s.state === 'frozen').length,
    },
  };

  writeFileSync(new URL(`run.${locale}.json`, import.meta.url), JSON.stringify(fixture, null, 2) + '\n');
  console.log(`run.${locale}.json ← ${f}: ${screens.length} screens, ${fixture.counts.shots} shots, ${fixture.epics.length} epics, manifest ${seed.manifest.id}`);
}

// Un-suffixed alias = en, for anything that still reads run.json directly.
const en = JSON.parse(readFileSync(new URL('./run.en.json', import.meta.url), 'utf8'));
writeFileSync(new URL('./run.json', import.meta.url), JSON.stringify(en, null, 2) + '\n');
console.log('run.json ← run.en.json (alias)');
