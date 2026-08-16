// appbox:provenance
// generator: appbox  licence: free  project: 662368770980
// Built with appbox (free tier) — https://appbox.dev
// JargonFacade — one rule for the whole app: every user-facing string and
// metric renders at the reader's level. Levels: plain / balanced / technical
// (default balanced). Copy variants live in the data spine (seed sparse
// overrides: textPlain / textBalanced — plain falls back to balanced falls
// back to technical). STATIC view copy lives in l10n/app_*.arb — the
// runtime's t() applies the same level rule (keyPlain / keyTechnical, base =
// balanced); views get it from the render context, not from here.
// Metrics keep raw values in fixtures; scores are computed here.

export const LEVELS = ['plain', 'balanced', 'technical'];

export const level = (prefs = {}) =>
  LEVELS.includes(prefs.jargon) ? prefs.jargon : 'balanced';

// Sparse-override picker: plain → textPlain ?? textBalanced ?? text.
export const pick = (obj, field, lv) => {
  const cap = lv[0].toUpperCase() + lv.slice(1);
  if (lv === 'plain') return obj[`${field}Plain`] ?? obj[`${field}Balanced`] ?? obj[field];
  if (lv === 'balanced') return obj[`${field}Balanced`] ?? obj[field];
  return obj[field];
};

// kimitail: match scores are a display heuristic, not metrology — the
// technical level always shows the raw metric. floor so the pass bar
// (ΔE 2.0 ↔ 95/100) is never rounded up onto itself.
export const scoreDeltaE = (de) => Math.max(0, Math.floor(100 - 2.5 * Number(de)));
export const scoreSsim = (ssim) => Math.round(1000 * Number(ssim)) / 10;
export const PASS_SCORE = 95; // the human-scale pass bar (ΔE ≤ 2.0)

// Catalog lookup with the former en literal as fallback while a key awaits
// merge into l10n/app_*.arb (same pattern as screens_facade.labelOf).
const tr = (translate, key, vars, fallback) => {
  const translated = translate(key, vars);
  return translated == key ? fallback : translated;
};

export const band = (score, translate = (key) => key) =>
  score >= 99 ? tr(translate, 'band.identical', null, 'identical to the eye')
  : score >= 95 ? tr(translate, 'band.nearIdentical', null, 'near-identical')
  : score >= 91 ? tr(translate, 'band.slightly', null, 'slightly different')
  : score >= 85 ? tr(translate, 'band.noticeably', null, 'noticeably different')
  : tr(translate, 'band.clearly', null, 'clearly different');

// Probe chips per level: plain/balanced lead with the /100 score; technical
// shows the raw trio. Each chip carries a title with the raw values.
export const probeChips = (probe, lv, translate = (key) => key) => {
  const de = scoreDeltaE(probe.deltaE);
  const ssim = scoreSsim(probe.ssim);
  if (lv === 'technical') {
    return [
      { text: `SSIM ${probe.ssim}`, title: tr(translate, 'probe.sim', null, 'pixel similarity') },
      { text: `${probe.skeleton}`, title: tr(translate, 'probe.skeleton', null, 'skeleton diff') },
      { text: `ΔE ${probe.deltaE}`, title: tr(translate, 'probe.colour', null, 'colour distance') },
    ];
  }
  const raw = `SSIM ${probe.ssim} · skeleton ${probe.skeleton} · ΔE ${probe.deltaE}`;
  const layout = probe.skeleton === 'match'
    ? tr(translate, 'probe.layoutExact', null, 'layout exact')
    : tr(translate, 'probe.layout', { state: probe.skeleton }, `layout ${probe.skeleton}`);
  if (lv === 'balanced') {
    return [
      { text: tr(translate, 'probe.structure', { n: ssim }, `${ssim}/100 structure`), title: raw },
      { text: layout, title: raw },
      { text: tr(translate, 'probe.colourScore', { n: de }, `${de}/100 colour`), title: raw },
    ];
  }
  return [
    { text: `${band(de, translate)} · ${de}/100`, title: raw },
    { text: layout, title: raw },
  ];
};
