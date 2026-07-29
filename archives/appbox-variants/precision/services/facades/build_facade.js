// BuildFacade — composes the run record into the shape the Build Monitor
// viewmodel wants. Session-held gate decisions and queued-run state are
// overlaid here, never in the fixture.
import * as runs from '../repositories/runs_repository.js';

const pendingGate = (run) =>
  run.gates.find((g) => g.state === 'pending') || null;

// decisions: { [gateId]: { verdict: 'approved'|'rejected', note, at } }
export const loopContext = ({ decisions = {}, runQueued = false, sev = 'all' } = {}) => {
  const run = structuredClone(runs.current());

  for (const [gateId, d] of Object.entries(decisions)) {
    const gate = run.gates.find((g) => g.id === gateId);
    if (gate) Object.assign(gate, { state: d.verdict, actor: 'you', at: d.at, decisionNote: d.note });
    const row = run.timeline.find((t) => t.kind === 'gate' && t.id === gateId);
    if (row) Object.assign(row, { state: d.verdict, actor: 'you', at: d.at, decisionNote: d.note });
  }

  const pending = pendingGate(run);
  const decidedList = run.gates.filter((g) => decisions[g.id]);
  const decided = decidedList[decidedList.length - 1] || null;
  const rejected = decided?.state === 'rejected' ? decided : null;

  return {
    run,
    runQueued,
    sev,
    pendingGate: pending,
    decidedGate: decided,
    pendingFindings: pending ? run.findings.filter((f) => f.gate === pending.id).length : 0,
    runState: rejected ? 'rejected' : pending ? 'blocked' : 'resuming',
    runStateLabel: rejected
      ? 'rejected — returned to scaffold'
      : pending ? 'blocked — awaiting human gate'
      : 'resuming — gate passed',
    filteredGroups: run.findingGroups
      .map((g) => ({
        ...g,
        findings: g.findings.filter((f) => sev === 'all' || f.severity === sev),
      }))
      .filter((g) => g.findings.length > 0),
    findingCount: run.findings.length,
  };
};
