// BuildFacade — composes the run fixture with session-scoped state
// (gate decisions, a queued next run) into exactly what loop_viewmodel needs.
import * as repo from '../repositories/build_repository.js';

// Human-gate decisions are the human's act; a POST lands them in the session
// and the facade overlays them onto the fixture's lifecycle.
function gatesWithDecisions(sessionData) {
  const decisions = sessionData.gateDecisions ?? {};
  return repo.humanGates().map((g) => {
    const d = decisions[g.id];
    if (!d) return g;
    return {
      ...g,
      state: d.decision,
      provenance: {
        by: 'Evan',
        shell: 'macOS shell',
        device: 'studio-mac (node m4-mini)',
        method: 'Touch ID',
        at: 'just now',
        hash: d.hash,
      },
      note: d.decision === 'rejected' ? d.note : null,
    };
  });
}

function stagesWithDecisions(gates) {
  const acceptance = gates.find((g) => g.id === 'build.acceptance');
  return repo.stages().map((s) => {
    if (s.kind === 'human') {
      const g = gates.find((x) => x.id === s.gate);
      return { ...s, state: g.state };
    }
    if (s.id === 'deploy' && acceptance.state === 'approved') {
      return { ...s, state: 'active', summary: 'Unlocked by build acceptance · ship.confirm gates release' };
    }
    if (s.id === 'deploy' && acceptance.state === 'rejected') {
      return { ...s, state: 'held', summary: 'Held — build rejected, back to coverage with your note' };
    }
    return s;
  });
}

function runWithState(sessionData, gates) {
  const run = { ...repo.run() };
  const acceptance = gates.find((g) => g.id === 'build.acceptance');
  if (acceptance.state === 'approved') {
    run.state = 'running';
    run.stateLabel = 'Running — deploy stage unlocked';
  } else if (acceptance.state === 'rejected') {
    run.state = 'held';
    run.stateLabel = 'Held — you rejected the build';
  }
  if (sessionData.queuedRun) {
    run.queued = 'Run #48 queued — starts when this one resolves';
  }
  return run;
}

export const loopContext = (sessionData = {}, severity = 'all') => {
  const gates = gatesWithDecisions(sessionData);
  const findingsByGate = Object.fromEntries(
    Object.entries(repo.findingsByGate()).map(([gate, list]) => [
      gate,
      severity === 'all' ? list : list.filter((f) => f.severity === severity),
    ]),
  );
  const stages = stagesWithDecisions(gates);
  return {
    run: runWithState(sessionData, gates),
    stages,
    gates,
    findingsByGate,
    severity,
    severityOptions: ['all', ...repo.filters().severities],
    filters: repo.filters(),
    evidence: repo.evidence(),
    counts: {
      findings: repo.counts().findings,
      gatesPending: gates.filter((g) => g.state === 'pending').length,
      stagesGreen: stages.filter((s) => s.state === 'green').length,
    },
  };
};

// Decide returns everything the decision round-trip re-renders.
export const decide = (sessionData, gateId, decision, note) => {
  const decisions = (sessionData.gateDecisions ??= {});
  decisions[gateId] = {
    decision,
    note: note || null,
    hash: decision === 'approved' ? 'c71b…e9d2' : '88d0…f4a6',
  };
  return loopContext(sessionData);
};

export const startRun = (sessionData) => {
  sessionData.queuedRun = true;
  return loopContext(sessionData);
};
