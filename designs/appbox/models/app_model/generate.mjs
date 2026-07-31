// appbox:provenance
// generator: appbox  licence: free  project: 662368770980
// Built with appbox (free tier) — https://appbox.dev
// Fixture generator — app_seed.<locale>.json → app.<locale>.json (+ app.json
// as the en alias). The fixture is the denormalized projection a template
// wants: chart bars carry precomputed heights, the pairing QR is a
// deterministic decorative matrix, counts are rolled up.
// Never hand-edit app*.json fixtures; edit the seed and re-run: node generate.mjs
import { readFileSync, readdirSync, writeFileSync } from 'node:fs';

const dir = new URL('.', import.meta.url);
const seeds = readdirSync(dir).filter((f) => /^app_seed\..+\.json$/.test(f));
if (!seeds.length) {
  console.error('no app_seed.<locale>.json found');
  process.exit(66);
}

// Bar heights as percentages of each chart's max — templates stay arithmetic-free.
const withHeights = (chart) => {
  const max = Math.max(...chart.bars.map((b) => b.value));
  return { ...chart, bars: chart.bars.map((b) => ({ ...b, height: Math.round((b.value / max) * 100) })) };
};

// Decorative QR-like matrix, derived deterministically from the pairing code so
// it is stable across renders. NOT scannable — the view's aria-label says so.
const QR_SIZE = 21;
const qrFor = (code) => {
  const prng = (() => {
    let a = [...code].reduce((acc, ch) => (acc * 31 + ch.charCodeAt(0)) >>> 0, 2166136261);
    return () => {
      a |= 0; a = (a + 0x6d2b79f5) | 0;
      let t = Math.imul(a ^ (a >>> 15), 1 | a);
      t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
      return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
    };
  })();
  const finder = (r, c) => {
    // 7×7 finder squares in three corners: ring on, gap off, 3×3 core on.
    for (const [or, oc] of [[0, 0], [0, QR_SIZE - 7], [QR_SIZE - 7, 0]]) {
      if (r >= or && r < or + 7 && c >= oc && c < oc + 7) {
        const i = r - or, j = c - oc;
        return i === 0 || i === 6 || j === 0 || j === 6 || (i >= 2 && i <= 4 && j >= 2 && j <= 4);
      }
    }
    return null;
  };
  const qr = [];
  for (let r = 0; r < QR_SIZE; r++) {
    let row = '';
    for (let c = 0; c < QR_SIZE; c++) {
      const f = finder(r, c);
      row += f === null ? (prng() < 0.45 ? '1' : '0') : f ? '1' : '0';
    }
    qr.push(row);
  }
  return qr;
};

for (const f of seeds.sort()) {
  const locale = f.match(/^app_seed\.(.+)\.json$/)[1];
  const seed = JSON.parse(readFileSync(new URL(f, import.meta.url), 'utf8'));
  const stats = Object.fromEntries(Object.entries(seed.analytics).map(([k, v]) => [k, withHeights(v)]));
  const fixture = {
    ...seed,
    stats,
    pairing: { ...seed.pairing, qr: qrFor(seed.pairing.code) },
    counts: { projects: seed.projects.length, gates: seed.gates.length },
  };
  writeFileSync(new URL(`app.${locale}.json`, import.meta.url), JSON.stringify(fixture, null, 2) + '\n');
  console.log(`app.${locale}.json ← ${f}: ${seed.projects.length} projects, ${seed.gates.length} gates, qr ${QR_SIZE}×${QR_SIZE}`);
}

// Un-suffixed alias = en, for anything that still reads app.json directly.
const en = JSON.parse(readFileSync(new URL('./app.en.json', import.meta.url), 'utf8'));
writeFileSync(new URL('./app.json', import.meta.url), JSON.stringify(en, null, 2) + '\n');
console.log('app.json ← app.en.json (alias)');
