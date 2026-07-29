// BuildFacade — composes the build repository + session overlay into exactly
// what the build.loop viewmodel renders. Session holds the human's acts
// (gate decisions, a started run) — the fixture holds everything the daemon did.
import * as build from '../repositories/build_repository.js';

const withDecisions = (session) =>
  build.gates().map((g) => {
    const d = session.decisions?.[g.id];
    return d
      ? { ...g, status: d.decision, actor: 'evan', at: d.at }
      : g;
  });

const runState = (session) => {
  const base = build.run();
  if (session.runStarted) return { ...base, state: 'running', haltReason: null };
  const d = session.decisions?.['gate.build']?.decision;
  if (d === 'approved')
    return { ...base, state: 'accepted', haltReason: 'accepted with findings — review resumed' };
  if (d === 'rejected')
    return { ...base, state: 'rejected', haltReason: 'rejected at build acceptance — re-run from coverage armed' };
  return base;
};

export const monitorContext = (session, severity = 'all') => ({
  run: runState(session),
  stages: build.stages(),
  gates: withDecisions(session),
  groups: findingsContext(session, severity).groups,
  severity,
  roll: build.rollup(),
  surfaces: build.surfaces(),
});

export const gatesContext = (session) => ({
  gates: withDecisions(session),
  run: runState(session),
  decision: session.decisions?.['gate.build']?.decision ?? null,
});

export const findingsContext = (session, severity = 'all') => {
  const items = build.findings(severity);
  const byGate = new Map();
  for (const f of items) {
    if (!byGate.has(f.gate)) byGate.set(f.gate, []);
    byGate.get(f.gate).push(f);
  }
  return {
    groups: [...byGate.entries()].map(([gate, fs]) => ({ gate, findings: fs })),
    severity,
    roll: build.rollup(),
  };
};
