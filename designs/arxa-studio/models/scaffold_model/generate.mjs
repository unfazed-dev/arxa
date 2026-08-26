// arxa:provenance
// generator: arxa  licence: free  project: 662368770980
// Built with arxa (free tier) — https://arxa.dev
// Fixture generator — scaffold_seed.<locale>.json → scaffold.<locale>.json (+
// scaffold.json as the en alias). The fixture is the denormalized projection
// the picker template wants: the three badge axes precomputed per kit, the
// dependency closure resolved (D5), counts per group, and the D2 removal
// warning payload (declaring screens) attached to each design-declared kit.
// Never hand-edit scaffold*.json fixtures; edit the seed and re-run:
//   node generate.mjs
import { readFileSync, readdirSync, writeFileSync } from 'node:fs';

const dir = new URL('.', import.meta.url);
const seeds = readdirSync(dir).filter((f) => /^scaffold_seed\..+\.json$/.test(f));
if (!seeds.length) {
  console.error('no scaffold_seed.<locale>.json found');
  process.exit(66);
}

// config/kit-registry.json declares no `depends` field, so the dependency
// edges D5 auto-includes are derived from `topology`, which is the only
// registry-grounded coupling signal: a `core-coupled` or `ui-tier` kit cannot
// compile without `core`. Deriving here (not hand-listing in the seed) keeps
// the rule auditable and the seed free of invented data.
const DEPS = {
  'core-coupled': ['core'],
  'ui-tier': ['core'],
  'app-integration': ['core', 'ui_library'],
};
// An explicit `depends` on the seed kit wins over the topology default. The
// registry declares no dependency edges at all, so any edge the picker shows
// is a design assertion and must be written down where a reader can see it —
// not conjured from a topology lookup.
const dependsOf = (k) => (k.depends || DEPS[k.topology] || []).filter((d) => d !== k.id);

// Visual-only grouping. The brief is explicit that the moodboard's 3–4 tier
// grouping is a layout suggestion, NOT a data contract — so it is computed
// here for presentation and never asserted as a field the pipeline reads.
const GROUP = {
  core: 'core', 'ui-tier': 'core', 'core-coupled': 'core',
  'app-integration': 'advanced',
};
const INTEGRATION = new Set(['payments', 'maps', 'notifications', 'analytics', 'auth', 'support']);
const PLATFORM = new Set(['permissions', 'media', 'documents', 'security', 'haptics', 'bluetooth', 'wifi', 'deploy']);
// An essential kit always reads as foundation regardless of its topology —
// `state` is topology:standalone but it is one of the three kits every app
// gets, and filing it under "Advanced" would be a lie the grouping tells.
const groupOf = (k, essentials) =>
  (essentials.includes(k.id) ? 'core' : null) ||
  GROUP[k.topology] ||
  (INTEGRATION.has(k.id) ? 'integrations' : PLATFORM.has(k.id) ? 'platform' : 'advanced');

// Readiness is axis 3 and is inform-only (D6): it never sets `blocked`, it
// only carries a badge state plus the deep-link target for the missing keys.
const readinessOf = (k) => ({
  state: k.readiness,
  ready: k.readiness === 'ready',
  missing: k.missing || [],
  count: (k.missing || []).length,
  module: k.credentialModule || null,
  // Inform-only: the picker is never gated on this. Deploy owns the hard stop.
  blocks: false,
});

for (const f of seeds.sort()) {
  const locale = f.match(/^scaffold_seed\.(.+)\.json$/)[1];
  const seed = JSON.parse(readFileSync(new URL(f, import.meta.url), 'utf8'));

  const byId = Object.fromEntries(seed.kits.map((k) => [k.id, k]));

  // Dependency closure over the selected set — anything pulled in that the
  // user did not hand-pick is flagged `auto` so the UI can distinguish it
  // (D5: "auto-included dependencies flagged distinctly from hand-picked").
  const selected = new Set(seed.kits.filter((k) => k.selected).map((k) => k.id));
  const autoAdded = new Set();
  let grew = true;
  while (grew) {
    grew = false;
    for (const id of [...selected]) {
      for (const d of dependsOf(byId[id] || {})) {
        if (!selected.has(d)) { selected.add(d); autoAdded.add(d); grew = true; }
      }
    }
  }

  const kits = seed.kits.map((k) => {
    const depends = dependsOf(k);
    const requiredBy = seed.kits
      .filter((o) => o.selected && dependsOf(o).includes(k.id))
      .map((o) => o.id);
    return {
      ...k,
      group: groupOf(k, seed.essentials || []),
      depends,
      requiredBy,
      // The pre-closure seed selection. The facade seeds its picked set from
      // THIS, not from `selected`, so generator closure and facade closure
      // start from the same place and agree by construction. Seeding from the
      // post-closure `selected` would swallow dependencies into the hand-picked
      // set and the D5 "added for you" notice would never fire.
      pickedByDesign: !!k.selected,
      selected: selected.has(k.id),
      auto: autoAdded.has(k.id),
      essential: (seed.essentials || []).includes(k.id),
      // Axis 1 + 2 + 3, kept as three separate fields on purpose. The brief
      // forbids collapsing them into one badge.
      provenanceAxis: { tier: k.provenance, confidence: k.confidence || null, evidenceScreen: k.evidenceScreen || null },
      maturityAxis: { phase: k.phase, native: k.phase !== 'stable' && k.phase !== 'n/a' },
      readinessAxis: readinessOf(k),
      // D2: removing a design-declared kit must name the declaring screens and
      // force a seed-backed fallback stub so the build still compiles.
      removal: {
        declared: (k.declaredBy || []).length > 0,
        declaringScreens: k.declaredBy || [],
        forcesFallback: (k.declaredBy || []).length > 0,
        fallback: (k.declaredBy || []).length > 0 ? 'seed-stub' : null,
      },
    };
  });

  const groups = ['core', 'integrations', 'platform', 'advanced'].map((id) => ({
    id,
    kits: kits.filter((k) => k.group === id),
    count: kits.filter((k) => k.group === id).length,
    selectedCount: kits.filter((k) => k.group === id && k.selected).length,
  })).filter((g) => g.count > 0);

  const chosen = kits.filter((k) => k.selected);
  const counts = {
    total: kits.length,
    selected: chosen.length,
    declared: chosen.filter((k) => k.provenance === 'declared').length,
    inferred: chosen.filter((k) => k.provenance === 'inferred').length,
    requested: chosen.filter((k) => k.provenance === 'requested').length,
    auto: chosen.filter((k) => k.auto).length,
    unready: chosen.filter((k) => !k.readinessAxis.ready).length,
  };

  // The D8 sidecar preview: wishlist (intake) + resolved (picker-confirmed,
  // provenance-labelled). The picker writes `resolved`; scaffold() consumes it
  // verbatim. Rendered read-only on the screen as the receipt of what will ship.
  const manifest = {
    ...seed.manifest,
    wishlist: kits.filter((k) => k.provenance === 'requested').map((k) => k.id),
    resolved: chosen.map((k) => ({ id: k.id, package: k.package, provenance: k.provenance, auto: k.auto })),
    todos: chosen.filter((k) => !k.readinessAxis.ready).map((k) => ({ id: k.id, missing: k.readinessAxis.missing })),
  };

  const fixture = {
    entitlement: seed.entitlement,
    essentials: seed.essentials || [],
    kits,
    groups,
    counts,
    manifest,
    states: seed.states,
  };

  writeFileSync(new URL(`scaffold.${locale}.json`, import.meta.url), `${JSON.stringify(fixture, null, 2)}\n`);
  if (locale === 'en') {
    writeFileSync(new URL('scaffold.json', import.meta.url), `${JSON.stringify(fixture, null, 2)}\n`);
  }
  console.log(`scaffold.${locale}.json — ${kits.length} kits, ${counts.selected} selected, ${counts.auto} auto, ${counts.unready} unready`);
}
