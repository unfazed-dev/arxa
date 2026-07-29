// BuildFacade — composes the run fixture with session-scoped state
// (gate decisions, composer messages, the artifact on the canvas) into
// exactly what loop_viewmodel needs.
import * as repo from '../repositories/build_repository.js';

export const DEFAULT_ARTIFACT = 'gate/build.acceptance';

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
  return run;
}

function messagesWithSession(sessionData, activeArtifact) {
  const extra = sessionData.extraMessages ?? [];
  return [...repo.narrative(), ...extra].map((m) => ({
    from: 'agent',
    tone: null,
    artifact: null,
    ...m,
    active: m.artifact === activeArtifact,
  }));
}

// The canvas renders ONE artifact at a time; ref is "kind/id".
function resolveArtifact(ref, { gates, stages, messages }) {
  const [kind, id] = (ref || DEFAULT_ARTIFACT).split('/');
  switch (kind) {
    case 'gate': {
      const gate = gates.find((g) => g.id === id);
      if (gate) return { kind, gate, ref };
      break;
    }
    case 'stage': {
      const stage = stages.find((s) => s.id === id);
      if (stage) return { kind, stage, stageCount: stages.length, ref };
      break;
    }
    case 'findings': {
      const list = repo.findingsByGate()[id];
      if (list) return { kind, gate: id, list, ref };
      break;
    }
    case 'chart':
      return { kind, chart: repo.chart(), ref };
    case 'log':
      return { kind, messages, ref };
    case 'evidence':
      return { kind, evidence: repo.evidence(), ref };
  }
  // Unknown artifact refs resolve to the default rather than erroring —
  // the canvas always has exactly one thing to show.
  if (ref !== DEFAULT_ARTIFACT) return resolveArtifact(DEFAULT_ARTIFACT, { gates, stages, messages });
  return { kind: 'log', messages, ref: DEFAULT_ARTIFACT };
}

export const loopContext = (sessionData = {}, ref = null) => {
  const gates = gatesWithDecisions(sessionData);
  const stages = stagesWithDecisions(gates);
  const activeArtifact = ref ?? sessionData.currentArtifact ?? DEFAULT_ARTIFACT;
  const messages = messagesWithSession(sessionData, activeArtifact);
  const parts = { gates, stages, messages };
  return {
    run: runWithState(sessionData, gates),
    stages,
    gates,
    counts: repo.counts(),
    messages,
    activeArtifact,
    artifact: resolveArtifact(activeArtifact, parts),
  };
};

export const showArtifact = (sessionData, ref) => {
  sessionData.currentArtifact = ref;
  return loopContext(sessionData, ref);
};

// The composer round-trip: append the user's message, then a simulated
// agent reply; the reply may pull a new artifact onto the canvas.
export const sendMessage = (sessionData, text) => {
  const extra = (sessionData.extraMessages ??= []);
  const seq = (sessionData.msgSeq = (sessionData.msgSeq ?? 0) + 1);
  extra.push({ id: `u-${seq}`, at: 'now', from: 'user', text });

  const lower = text.toLowerCase();
  const reply = repo.replies().find((r) => r.match.some((k) => lower.includes(k)))
    ?? repo.replyFallback();
  extra.push({
    id: `a-${seq}`, at: 'now', from: 'agent', text: reply.text,
    artifact: reply.artifact, tone: reply.artifact ? 'action' : null,
  });

  const ref = reply.artifact ?? sessionData.currentArtifact ?? DEFAULT_ARTIFACT;
  return showArtifact(sessionData, ref);
};

// Gate decision: record it, mint provenance, narrate the consequence.
export const decide = (sessionData, gateId, decision, note) => {
  const decisions = (sessionData.gateDecisions ??= {});
  decisions[gateId] = {
    decision,
    note: note || null,
    hash: decision === 'approved' ? 'c71b…e9d2' : '88d0…f4a6',
  };
  const gate = repo.humanGates().find((g) => g.id === gateId);
  const label = gate ? gate.label.toLowerCase() : gateId;
  const extra = (sessionData.extraMessages ??= []);
  const seq = (sessionData.msgSeq = (sessionData.msgSeq ?? 0) + 1);
  extra.push({
    id: `a-${seq}`, at: 'now', from: 'agent',
    text: decision === 'approved'
      ? `You approved ${label} — provenance c71b…e9d2 minted via Touch ID on studio-mac. Deploy stage unlocked.`
      : `You rejected ${label} — run held, back to coverage with your note.`,
    artifact: `gate/${gateId}`,
    tone: decision === 'approved' ? 'action' : 'fail',
  });
  return showArtifact(sessionData, `gate/${gateId}`);
};
