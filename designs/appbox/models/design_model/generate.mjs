// Fixture generator — seed.json → run.json. The fixture is the denormalized
// projection a template wants: shot ids minted per rung, per-rung layout
// notes per wire kind, the epic filter list, summary counts.
// Never hand-edit run.json; edit the seed and re-run: node generate.mjs
import { readFileSync, writeFileSync } from 'node:fs';

const seed = JSON.parse(readFileSync(new URL('./seed.json', import.meta.url), 'utf8'));

// What the layout does at each rung, per wire kind — the "literal parity"
// story told in one line per shot.
const RUNG_NOTES = {
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
};

// kimitail: fake-but-stable shot ids, good enough for a prototype fixture.
const shortHash = (s) => {
  let h = 0;
  for (const ch of s) h = (h * 31 + ch.charCodeAt(0)) >>> 0;
  return h.toString(16).padStart(8, '0');
};

const screens = seed.screens.map((s) => ({
  ...s,
  rungs: s.rungs.map((r) => ({
    ...r,
    shot: `sh_${shortHash(s.id + r.rung).slice(0, 4)}…${shortHash(r.rung + s.id).slice(0, 4)}`,
    note: RUNG_NOTES[s.wire]?.[r.rung] ?? '',
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

writeFileSync(new URL('./run.json', import.meta.url), JSON.stringify(fixture, null, 2) + '\n');
console.log(`run.json: ${screens.length} screens, ${fixture.counts.shots} shots, ${fixture.epics.length} epics, manifest ${seed.manifest.id}`);
