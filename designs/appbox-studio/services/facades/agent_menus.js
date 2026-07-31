// appbox:provenance
// generator: appbox  licence: free  project: 662368770980
// Built with appbox (free tier) — https://appbox.dev
// AgentMenus — the composer's LLM model menu. ONE module so every tab
// narrates the same agent; the selection lives on sessionData.agent.model
// (shared across tabs — it is the same agent everywhere), and the menu
// hrefs are scoped to the rendered surface's base, so a pick swaps THAT
// surface's stage (same rule as the context filmstrip ×).
const MODELS = [
  { id: 'k3', label: 'K3', blurb: 'Chat & Agent, flagship all-rounder' },
  { id: 'k3-swarm', label: 'K3 Swarm', blurb: 'Massive search, batch processing, and more in one go' },
  { id: 'k2.6-agent', label: 'K2.6 Agent', blurb: 'Research, slides, websites, docs, sheets' },
];

// Blurb catalog keys per model id; the en literal above stays the fallback
// while the key awaits merge into l10n/app_*.arb.
const BLURB_KEY = {
  'k3': 'agent.model.k3.blurb',
  'k3-swarm': 'agent.model.k3Swarm.blurb',
  'k2.6-agent': 'agent.model.k26Agent.blurb',
};

const agent = (sessionData) => (sessionData.agent ??= {});
const current = (a) => MODELS.find((m) => m.id === a.model) ?? MODELS[2]; // K2.6 Agent

export const modelMenuFor = (sessionData, base, t = (k) => k) => {
  const on = current(agent(sessionData));
  const blurbOf = (m) => {
    const v = t(BLURB_KEY[m.id]);
    return v == BLURB_KEY[m.id] ? m.blurb : v;
  };
  return {
    label: on.label,
    options: MODELS.map((m) => ({ ...m, blurb: blurbOf(m), active: m.id === on.id, href: `${base}/model/${m.id}` })),
  };
};

export const setModel = (sessionData, id) => {
  if (MODELS.some((m) => m.id === id)) agent(sessionData).model = id;
};
