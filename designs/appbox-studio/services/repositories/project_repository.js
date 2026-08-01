// appbox:provenance
// generator: appbox  licence: free  project: 662368770980
// Built with appbox (free tier) — https://appbox.dev
// ProjectRepository — the CURRENT PROJECT's intake outputs (registry, flows)
// and surface partials, live-read through the server overlay. The design
// viewer's flows lens, the flow-driven stub chrome (tab bar, advance links)
// and the intake flows surface all read from here.
import { readProjectFixture } from './fixture_reader.js';

export const registry = () => readProjectFixture('intake/registry.json');
export const flows = () => readProjectFixture('intake/flows.json');
export const registryEntry = (id) => registry().find((e) => e.id === id);

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
export const nextEdge = (screenId) => {
  try {
    for (const f of flows()) {
      for (const e of f.edges ?? []) {
        if (e.from === screenId) return { ...e, flow: f.id, flowName: f.name };
      }
    }
  } catch {
    // no project overlaid — no flow chrome
  }
  return null;
};

// Does the project ship a bespoke partial for this screen kind?
// (ui/project/<kind>.html in the overlay's template map — the worker injects
// it as globalThis.__templates; absent → the stub's generic fallback renders.)
export const hasPartial = (kind) =>
  typeof globalThis.__templates?.[`ui/project/${kind}.html`] === 'string';
