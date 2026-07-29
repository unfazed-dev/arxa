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

const agent = (sessionData) => (sessionData.agent ??= {});
const current = (a) => MODELS.find((m) => m.id === a.model) ?? MODELS[2]; // K2.6 Agent

export const modelMenuFor = (sessionData, base) => {
  const on = current(agent(sessionData));
  return {
    label: on.label,
    options: MODELS.map((m) => ({ ...m, active: m.id === on.id, href: `${base}/model/${m.id}` })),
  };
};

export const setModel = (sessionData, id) => {
  if (MODELS.some((m) => m.id === id)) agent(sessionData).model = id;
};
