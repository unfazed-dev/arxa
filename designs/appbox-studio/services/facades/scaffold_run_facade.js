// appbox:provenance
// generator: appbox  licence: free  project: 662368770980
// Built with appbox (free tier) — https://appbox.dev
//
// ScaffoldRunFacade — the `c` object every scaffold.run template macro reads.
//
// WHAT THIS SCREEN IS (D24): scaffolding is a fast DETERMINISTIC TRANSFORM of
// an already-frozen structure.json. No LLM call, no subprocess, no network. It
// is measured in milliseconds, so there is nothing to watch. That single fact
// decides the whole shape of this facade: there is no `progress`, no `stage`,
// no `percent` and no `elapsed` field anywhere below, because a screen that
// exposes them invites a template to animate them, and an animated progress
// ring for a synchronous function call is a lie about where time goes.
//
// A run is therefore in exactly one of five READ states, never a sixth
// "running" one:
//   pre       — structure frozen, kits chosen, nothing written yet (the gate)
//   completed — every write landed clean
//   warning   — everything landed, but a kit carried unmet readiness through
//   failed    — a write was refused; the run rolled back
//   blocked   — the precondition is absent (structure not frozen)
import * as repo from '../repositories/scaffold_run_repository.js';

const STATES = ['pre', 'completed', 'warning', 'failed', 'blocked'];
const PERSISTABLE_PANELS = ['composer', 'activity'];
const PANEL_SIZES = ['s', 'm', 'l'];

const run = (sessionData = {}) => (sessionData.scaffoldRun ??= {});

/**
 * context — the `c` object every scaffold.run template macro reads.
 *
 * @param session  server-held session (holds panelSize)
 * @param t        translator
 * @param locale   active locale
 * @param screen   requested lens state: pre | completed | warning | failed | blocked
 */
export const context = (session = {}, t = (k) => k, locale = 'en', screen = 'completed') => {
  const state = STATES.includes(screen) ? screen : 'completed';
  const s = run(session);

  const structure = repo.structure(locale);
  const manifest = repo.manifest(locale);
  const kits = repo.kits(locale);
  const counts = repo.counts(locale);
  const deltas = repo.deltas(locale);
  const states = repo.states(locale);
  const unready = repo.unready(locale);

  // Warnings are READINESS warnings, and readiness is inform-only (D6): it
  // never gates the scaffold, only deploy. So they ride on the completed
  // receipt as a note, never as an error, and never suppress the file list.
  const warnings = state === 'warning' ? repo.warnings(locale) : [];

  // The failed receipt lists only what landed BEFORE the stop, so the printed
  // list and the printed count cannot contradict each other.
  const all = repo.writes(locale);
  const writes = state === 'pre' || state === 'blocked'
    ? []
    : state === 'failed'
      ? all.slice(0, states.failed.wrote)
      : all;

  const done = state === 'completed' || state === 'warning';

  return {
    // --- shell chrome (read by _shared.html) ------------------------------
    // `panel` is the grid's data-panel string (which panel is emphasised);
    // the persisted s/m/l widths are a separate map, not the same field.
    panel: s.panel || 'main',
    panelSizes: s.panelSize || {},
    stageEyebrow: t('scaffold.run.eyebrow'),
    chips: [
      { label: t('scaffold.run.chip.structure', { revision: structure.revision }) },
      { label: t('scaffold.run.chip.kits', { count: counts.kits }) },
    ],
    thread: [
      { kind: 'event', text: t('scaffold.run.thread.frozen', { screens: structure.screens }) },
      {
        from: 'agent',
        text: t(`scaffold.run.thread.${state}`),
        link: done ? { href: '/build', label: t('scaffold.run.thread.toBuild') } : null,
      },
    ],
    activity: {
      label: t('scaffold.run.activity.label'),
      views: [],
      // Per-kit, not per-stage: the unit of work is a kit, and it either
      // contributed files or it did not.
      items: kits.map((k) => ({
        label: t(`scaffold.kit.${k.id}`),
        meta: t(`scaffold.run.activity.${k.ready ? 'ready' : 'needsKeys'}`),
        active: !k.ready && state === 'warning',
      })),
    },

    // --- the receipt ------------------------------------------------------
    state,
    isPre: state === 'pre',
    isDone: done,
    isFailed: state === 'failed',
    isBlocked: state === 'blocked',
    hasWarnings: warnings.length > 0,
    structure,
    manifest,
    kits,
    writes,
    warnings,
    unready,
    deltas,
    counts,
    failure: state === 'failed' ? states.failed : null,
    blocked: state === 'blocked' ? states.blocked : null,
    runHref: '/scaffold/run?state=completed',
    backHref: '/scaffold',
  };
};

// Panel width grip: s/m/l persisted per side, whole-panel re-render.
export const setPanelSize = (sessionData, panel, size, t = (k) => k, locale = 'en', screen = 'completed') => {
  if (PERSISTABLE_PANELS.includes(panel) && PANEL_SIZES.includes(size)) {
    (run(sessionData).panelSize ??= {})[panel] = size;
  }
  return context(sessionData, t, locale, screen);
};

export default { context, setPanelSize };
