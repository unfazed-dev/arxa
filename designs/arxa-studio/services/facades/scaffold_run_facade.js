// arxa:provenance
// generator: arxa  licence: free  project: 662368770980
// Built with arxa (free tier) — https://arxa.dev
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
// The header's account chip (_shared.html accountChip) reads the picker
// fixture's seeded entitlement — composing a second repository is exactly
// what a facade is for. Run has no entitlement lens of its own; the chip
// follows the REAL seeded session (same accountState helper the picker
// gate derives from), falling back to the fixture's plan label.
import * as pickerRepo from '../repositories/scaffold_repository.js';
import { accountState } from './app_facade.js';

const STATES = ['pre', 'completed', 'warning', 'failed', 'blocked'];
const PERSISTABLE_PANELS = ['composer', 'activity'];
const PANEL_SIZES = ['s', 'm', 'l'];

const run = (sessionData = {}) => (sessionData.scaffoldRun ??= {});

// Sibling convention (design/intake/build): the facade resolves the persisted
// map down to ONE scalar for the panel the spec describes, and the template
// passes `size:`/`sizeHref:`. The template never reads the map. Emitting a map
// (`panelSizes`) instead is why this screen's grip never appeared: the persist
// route was live the whole time, but `activity_panel.open()` gates `resize` on
// `spec.sizeHref`, so with no href there was no grip, and width fell to 's'.
const panelSizeFor = (runState, panel) => (PANEL_SIZES.includes(runState.panelSize?.[panel]) ? runState.panelSize[panel] : 's');

/**
 * context — the `c` object every scaffold.run template macro reads.
 *
 * @param session  server-held session (holds panelSize)
 * @param t        translator
 * @param locale   active locale
 * @param screen   requested lens state: pre | completed | warning | failed | blocked
 */
export const context = (session = {}, translate = (key) => key, locale = 'en', screen = 'completed') => {
  const state = STATES.includes(screen) ? screen : 'completed';
  const runState = run(session);

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
    // `panelSize` is the activity panel's persisted width — a different field.
    panel: runState.panel || 'main',
    panelSize: panelSizeFor(runState, 'activity'),
    panelSizeHref: '/scaffold/run/panel/size/activity/',
    stageEyebrow: translate('scaffold.run.eyebrow'),
    // brief (c): the shell header carries the entitlement/account element.
    entitlement: {
      ...pickerRepo.entitlement(locale),
      ...accountState(session),
      accountHref: '/workspace/plans',
    },
    chips: [
      { label: translate('scaffold.run.chip.structure', { revision: structure.revision }) },
      { label: translate('scaffold.run.chip.kits', { count: counts.kits }) },
    ],
    thread: [
      { kind: 'event', text: translate('scaffold.run.thread.frozen', { screens: structure.screens }) },
      {
        from: 'agent',
        text: translate(`scaffold.run.thread.${state}`),
        link: done ? { href: '/build', label: translate('scaffold.run.thread.toBuild') } : null,
      },
      // The user's own words, and nothing after them. A frozen receipt has no
      // agent left to answer: synthesising a reply would claim the run read a
      // message that arrived after it finished (D24 — the transform already ran
      // to completion before this screen could be rendered at all).
      ...(runState.messages || []).map((text) => ({ from: 'user', text })),
    ],
    activity: {
      label: translate('scaffold.run.activity.label'),
      views: [],
      // Per-kit, not per-stage: the unit of work is a kit, and it either
      // contributed files or it did not.
      items: kits.map((kit) => ({
        label: translate(`scaffold.kit.${kit.id}`),
        meta: translate(`scaffold.run.activity.${kit.ready ? 'ready' : 'needsKeys'}`),
        active: !kit.ready && state === 'warning',
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
    // The receipt is read-only about the RUN — nothing here re-runs it — but the
    // user can still record a note against the outcome they are reading. The
    // lens state travels IN the action because `sendMessage` re-renders the
    // panel from `?state=`: posting from a bare path would answer a note left on
    // the `failed` receipt with the `completed` one. Routed at
    // routes.scaffold.js (POST /scaffold/run/messages) BEFORE this line was set.
    composerAction: `/scaffold/run/messages?state=${state}`,
  };
};

// Panel width grip: s/m/l persisted per side, whole-panel re-render.
export const setPanelSize = (sessionData, panel, size, translate = (key) => key, locale = 'en', screen = 'completed') => {
  if (PERSISTABLE_PANELS.includes(panel) && PANEL_SIZES.includes(size)) {
    (run(sessionData).panelSize ??= {})[panel] = size;
  }
  return context(sessionData, translate, locale, screen);
};

// The composer on a read receipt records what the user said and stops there.
// Persisted per session so the note survives the next whole-panel re-render;
// no reply is synthesised (see the thread comment in `context`).
export const sendMessage = (sessionData, text, translate = (key) => key, locale = 'en', screen = 'completed') => {
  const body = String(text ?? '').trim();
  if (body) (run(sessionData).messages ??= []).push(body);
  return context(sessionData, translate, locale, screen);
};

export default { context, setPanelSize, sendMessage };
