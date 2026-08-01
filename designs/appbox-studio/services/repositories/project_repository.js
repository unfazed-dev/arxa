// appbox:provenance
// generator: appbox  licence: free  project: 662368770980
// Built with appbox (free tier) — https://appbox.dev
// ProjectRepository — the CURRENT PROJECT's intake outputs (registry, flows)
// and surface partials, live-read through the server overlay. The design
// viewer's flows lens, the flow-driven stub chrome (tab bar, advance links)
// and the intake flows surface all read from here.
import { readProjectFixture, writeProjectFixture } from './fixture_reader.js';

export const registry = () => readProjectFixture('intake/registry.json');
export const flows = () => readProjectFixture('intake/flows.json');
export const registryEntry = (id) => registry().find((e) => e.id === id);

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
