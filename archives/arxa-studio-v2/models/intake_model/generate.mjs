// arxa:provenance
// generator: arxa  licence: free  project: 662368770980
// Built with arxa (free tier) — https://arxa.dev
// Fixture generator — intake_seed.<locale>.json → intake.<locale>.json (+
// intake.json as the en alias). The fixture is the denormalized projection a
// template wants: stories carry stable ids, counts are precomputed (per
// priority, per release), moodboard shots carry ids + served src paths.
// Never hand-edit intake*.json fixtures; edit the seed and re-run: node generate.mjs
import { readFileSync, readdirSync, writeFileSync } from 'node:fs';

const dir = new URL('.', import.meta.url);
const seeds = readdirSync(dir).filter((f) => /^intake_seed\..+\.json$/.test(f));
if (!seeds.length) {
  console.error('no intake_seed.<locale>.json found');
  process.exit(66);
}

const slug = (s) => s.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/(^-|-$)/g, '');

for (const f of seeds.sort()) {
  const locale = f.match(/^intake_seed\.(.+)\.json$/)[1];
  const seed = JSON.parse(readFileSync(new URL(f, import.meta.url), 'utf8'));

  // Stories get stable ids (s-<n>, document order) for canvas deep-links, and a
  // trace to the brief's surface inventory by feature label.
  const surfaceByLabel = {};
  for (const s of seed.brief.surfaces) (surfaceByLabel[s.label] ??= []).push(s.id);

  let n = 0;
  const counts = { epics: seed.map.epics.length, features: 0, stories: 0, must: 0, should: 0, could: 0, byRelease: {} };
  const epics = seed.map.epics.map((e) => ({
    id: slug(e.name),
    name: e.name,
    storyCount: e.features.reduce((a, f) => a + f.stories.length, 0),
    features: e.features.map((f) => {
      counts.features += 1;
      return {
        id: slug(f.name),
        name: f.name,
        stories: f.stories.map((s) => {
          n += 1;
          counts.stories += 1;
          counts[s.priority] += 1;
          counts.byRelease[s.release] = (counts.byRelease[s.release] ?? 0) + 1;
          return { id: `s-${n}`, name: s.name, priority: s.priority, release: s.release, epic: e.name, feature: f.name, surfaces: surfaceByLabel[f.name] ?? [] };
        }),
      };
    }),
  }));

  const releases = seed.map.releases.map((r) => ({ ...r, stories: counts.byRelease[r.name] ?? 0 }));

  // Moodboard shots get ids (board--file) and their served path under assets/.
  const boards = seed.moodboard.boards.map((b) => ({
    ...b,
    references: b.references.map((r) => ({
      ...r,
      shot: {
        ...r.shot,
        id: `${b.id}--${r.shot.file.replace(/\.png$/, '')}`,
        src: `/assets/images/moodboard/${b.id}/${r.shot.file}`,
      },
    })),
  }));
  const refCount = boards.reduce((a, b) => a + b.references.length, 0);

  const fixture = {
    ...seed,
    map: { releases, epics },
    moodboard: { ...seed.moodboard, boards, counts: { boards: boards.length, references: refCount, shots: refCount } },
    counts,
  };

  writeFileSync(new URL(`intake.${locale}.json`, import.meta.url), JSON.stringify(fixture, null, 2) + '\n');
  console.log(`intake.${locale}.json ← ${f}: ${counts.epics} epics, ${counts.features} features, ${counts.stories} stories, ${boards.length} moodboards (${refCount} shots)`);
}

// Un-suffixed alias = en, for anything that still reads intake.json directly.
const en = JSON.parse(readFileSync(new URL('./intake.en.json', import.meta.url), 'utf8'));
writeFileSync(new URL('./intake.json', import.meta.url), JSON.stringify(en, null, 2) + '\n');
console.log('intake.json ← intake.en.json (alias)');
