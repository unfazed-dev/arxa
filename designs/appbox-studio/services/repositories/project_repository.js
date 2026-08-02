// appbox:provenance
// generator: appbox  licence: free  project: 662368770980
// Built with appbox (free tier) — https://appbox.dev
// ProjectRepository — the CURRENT PROJECT's intake outputs (registry, flows,
// answers) and surface partials, live-read through the server overlay. The design
// viewer's flows lens, the flow-driven stub chrome (tab bar, advance links)
// and the intake flows surface all read from here.
import { readProjectFixture, writeProjectFixture } from './fixture_reader.js';

export const registry = () => readProjectFixture('intake/registry.json');
export const flows = () => readProjectFixture('intake/flows.json');
// The intake interview's recorded answers ({product, audience, direction, …},
// each {value, provenance}) — the intake surfaces prefill from here.
export const answers = () => readProjectFixture('intake/answers.json');
export const registryEntry = (id) => registry().find((e) => e.id === id);

// Flow edits (move/add/remove from the viewer) write the whole flows.json
// back through the server's confined channel; writeProjectFixture busts the
// read cache, so the re-render that follows sees the new bytes.
export const writeFlows = (flows) => writeProjectFixture('intake/flows.json', flows);

// The overlaid project's settings/project.json ({name, targets, locales}) —
// null when artifact-only serving.
export const settings = () => {
  try {
    return readProjectFixture('settings/project.json');
  } catch {
    return null;
  }
};
export const currentName = () => settings()?.name ?? null;

// The project's tab bar: registry entries flagged tab:true, in registry order
// (the scaffolder's shell group — same source the route table will read).
// Empty when no project is overlaid (artifact-only serving).
export const tabs = () => {
  try {
    return registry().filter((e) => e.tab === true);
  } catch {
    return [];
  }
};

// The flow a screen starts/advances in: the next edge's (to, trigger, action)
// for splash→startup→auth style auto-advance + tap-through chrome.
//
// `flowId` scopes the search to ONE flow. Without it the first match across all
// flows wins — a guess whenever a screen sits in two. portalo.home is in
// flow-browse-buy (→ checkout) AND flow-account (→ account), so authoring order
// silently decided where "next" went. The flows lens knows its row and passes
// it; the views lens has no row, which is why it no longer offers an interactive
// mode at all rather than advancing along a guessed edge. See
// docs/plans/design-viewer-per-lens-hover-and-flow-mode.md.
export const nextEdge = (screenId, flowId = null) => {
  try {
    for (const f of flows()) {
      if (flowId && f.id !== flowId) continue;
      for (const e of f.edges ?? []) {
        if (e.from === screenId) return { ...e, flow: f.id, flowName: f.name };
      }
    }
  } catch {
    // no project overlaid — no flow chrome
  }
  return null;
};

// Where else does this screen go? Flows connect through SHARED SCREEN IDS —
// a screen that terminates one flow and heads another IS the join, and that is
// already true in authored data (portalo.home ends flow-onboarding and heads
// both flow-browse-buy and flow-account). No `toFlow` key, nothing to author,
// nothing that can disagree with the ids.
//
// Deliberately separate from nextEdge rather than a mode of it. nextEdge
// answers "where does this row go next" and must stay single-valued and
// row-scoped or it is guessing; this answers "which OTHER flows continue from
// here" and is inherently a LIST. Collapsing them would reintroduce exactly the
// first-match-across-all-flows guess that scoping nextEdge removed.
//
// `fromFlowId` is DEFENSIVE, not load-bearing — say so rather than let a
// future reader assume a check protects it. The only caller asks about a row's
// LAST tile, which by construction has no outgoing edge in its own flow, so the
// skip cannot fire there. It exists so the function is correct for any caller
// (and for a cyclic flow, where it could). Do not write a "excludes the source
// flow" check against portalo: it would pass with the line deleted.
export const handoffs = (screenId, fromFlowId = null) => {
  const out = [];
  try {
    for (const f of flows()) {
      if (f.id === fromFlowId) continue;
      const e = (f.edges ?? []).find((x) => x.from === screenId);
      if (e) out.push({ flow: f.id, flowName: f.name, to: e.to, trigger: e.trigger });
    }
  } catch { /* no project overlaid — no hand-offs */ }
  return out;
};

// EVERY outgoing edge for a screen, across every flow — the explode column's
// "what does tapping this do?" join. Unlike nextEdge this is intentionally
// unscoped and plural: the question is "what can this screen's elements fire",
// and a screen genuinely sits in several flows. Nothing here picks a winner,
// so nothing here can guess wrong.
export const edgesFrom = (screenId) => {
  const out = [];
  try {
    for (const f of flows()) {
      for (const e of f.edges ?? []) {
        if (e.from !== screenId) continue;
        out.push({
          flow: f.id, flowName: f.name, to: e.to,
          trigger: e.trigger ?? null, element: e.element ?? null,
        });
      }
    }
  } catch { /* no project overlaid — no joins */ }
  return out;
};

// Does the project ship a bespoke partial for this screen kind?
// (ui/project/<kind>.html in the overlay's template map — the worker injects
// it as globalThis.__templates; absent → the stub's generic fallback renders.)
export const hasPartial = (kind) =>
  typeof globalThis.__templates?.[`ui/project/${kind}.html`] === 'string';

// ---------- the projects grid (dashboard live-read) ----------
const origin = () => new URL('../../', import.meta.url).href.replace(/\/$/, '');

// Every project in ~/.appbox with its derived stage + output counts, plus the
// current marker. No appbox home / no endpoint → an empty honest grid.
export const listProjects = async () => {
  try {
    const res = await fetch(`${origin()}/__projects`);
    if (!res.ok) return { current: null, projects: [] };
    return await res.json();
  } catch {
    return { current: null, projects: [] };
  }
};

// Point `current` at another project (POST /__project_use).
export const useProject = async (name) => {
  const res = await fetch(`${origin()}/__project_use`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ name }),
  });
  if (!res.ok) throw new Error(`project use failed (${res.status}): ${await res.text()}`);
};

// The wizard's create: a real project on disk (settings/project.json written
// through the write channel's project override creates the whole layout).
export const createProject = async (name, targets) => {
  await writeProjectFixture(
    'settings/project.json',
    { name, targets: targets.length ? targets : ['web'], locales: ['en', 'pl'] },
    { project: name },
  );
};
