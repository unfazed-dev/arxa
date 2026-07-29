// BuildFacade — composes the run fixture with session-scoped state (gate
// decisions, posted messages, empty-state flag) into exactly what
// loop_viewmodel needs. The build loop is rendered AS a conversation:
// pipeline events resolve to thread cards, user posts get a simulated
// agent card in reply.
import * as repo from '../repositories/build_repository.js';

// --- gate/stage/run state overlays (decisions live in the session) ---

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

// --- the thread ---

// Donut segments from LIVE gate state (fixture numbers predate decisions).
function liveGateChart(gates) {
  const order = ['approved', 'pending', 'rejected', 'queued'];
  let acc = 0;
  const segments = order.map((state) => {
    const count = gates.filter((g) => g.state === state).length;
    const seg = { state, count, from: Math.round(acc), to: Math.round(acc + (count / gates.length) * 100) };
    acc += (count / gates.length) * 100;
    return seg;
  }).filter((s) => s.count > 0);
  const approved = gates.filter((g) => g.state === 'approved').length;
  return { total: gates.length, approved, segments };
}

// Seeded events reference live gate state, so a decided gate re-renders
// its card inside the conversation history.
function baseThread(gates) {
  return repo.thread().map((e) => {
    if ((e.type === 'gate-decision' || e.type === 'gate-pending') && e.gate) {
      return { ...e, gate: gates.find((g) => g.id === e.gate) };
    }
    return e;
  });
}

// Simulated agent reply — a purpose-built card per intent, never a
// markdown wall. Complexity lives behind the input.
function agentReply(text) {
  const t = (text || '').toLowerCase();
  if (/history|gates/.test(t)) {
    return { at: 'now', type: 'gates', text: 'Here is where every human gate stands.' };
  }
  if (/why|fail|review|coverage|finding|red/.test(t)) {
    return {
      at: 'now', type: 'findings',
      text: 'Coverage went red on attempt 1 — stop-on-red held the run. Three findings, all fixed in attempt 2:',
    };
  }
  if (/ship|testflight|deploy|release/.test(t)) {
    return { at: 'now', type: 'deploy' };
  }
  if (/long|duration|time|pace|slow/.test(t)) {
    return { at: 'now', type: 'pace' };
  }
  return {
    at: 'now', type: 'agent-text',
    text: 'Run #47 is paused at build acceptance — coverage recovered on attempt 2, review is clean. The call is yours: approve to unlock deploy, reject to send it back with a note.',
  };
}

export const loopContext = (sessionData = {}) => {
  const gates = gatesWithDecisions(sessionData);
  const stages = stagesWithDecisions(gates);
  const posted = sessionData.messages ?? [];
  return {
    run: runWithState(sessionData, gates),
    stages,
    gates,
    findings: repo.findings(),
    findingsByGate: repo.findingsByGate(),
    evidence: repo.evidence(),
    pace: repo.pace(),
    gateChart: liveGateChart(gates),
    empty: sessionData.empty === true,
    thread: [...baseThread(gates), ...posted],
    counts: {
      findings: repo.counts().findings,
      gatesPending: gates.filter((g) => g.state === 'pending').length,
      stagesGreen: stages.filter((s) => s.state === 'green').length,
    },
  };
};

// Composer round-trip: append the user message + a simulated agent reply.
// Returns the context plus a flag so the handler can full-refresh out of
// the empty state (centered composer → thread) in one hop.
export const postMessage = (sessionData, text) => {
  const wasEmpty = sessionData.empty === true;
  sessionData.empty = false;
  const messages = (sessionData.messages ??= []);
  const appended = [];
  const clean = (text || '').trim();
  if (clean) appended.push({ at: 'now', type: 'user', text: clean });
  appended.push(agentReply(clean));
  messages.push(...appended);
  return { ...loopContext(sessionData), wasEmpty, appended };
};

export const decide = (sessionData, gateId, decision, note) => {
  const decisions = (sessionData.gateDecisions ??= {});
  decisions[gateId] = {
    decision,
    note: note || null,
    hash: decision === 'approved' ? 'c71b…e9d2' : '88d0…f4a6',
  };
  // The decision is narrated back into the thread as an agent message.
  const label = gateId === 'build.acceptance' ? 'Build acceptance' : gateId;
  const messages = (sessionData.messages ??= []);
  messages.push({
    at: 'now',
    type: 'agent-text',
    text: decision === 'approved'
      ? `${label} approved — provenance minted on this device. Deploy is unlocked; ship.confirm still gates the release.`
      : `${label} rejected — the run is held and goes back to coverage with your note.`,
  });
  return loopContext(sessionData);
};

export const newThread = (sessionData) => {
  sessionData.empty = true;
  sessionData.messages = [];
  return loopContext(sessionData);
};

export const canvasContext = (payload) => {
  const a = repo.artifacts()[payload];
  if (a) return { kind: a.kind, title: a.title, lines: a.lines, pretty: a.pretty };
  if (payload === 'evidence') {
    return { kind: 'evidence', title: 'Per-surface evidence — probe vs frozen golden', evidence: repo.evidence() };
  }
  return null;
};
