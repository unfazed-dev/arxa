// BuildFacade — composes the run fixture with session-scoped state (gate
// decisions, the message thread) into exactly what loop_viewmodel needs.
// The focus pattern lives here: one hero (a pending gate, else the running
// stage), finished stages as one-liners, queued stages as ghost outlines.
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

// demo = 'gate' (default — build acceptance awaits) | 'running' (coverage
// mid-attempt, nothing awaiting). Request-scoped; drives the demo states.
export const loopContext = (sessionData = {}, demo = 'gate') => {
  const gates = gatesWithDecisions(sessionData);
  const acceptance = gates.find((g) => g.id === 'build.acceptance');
  const decided = acceptance.state === 'approved' || acceptance.state === 'rejected';
  const running = demo === 'running' && !decided;

  const run = { ...repo.run() };
  if (decided) {
    run.state = acceptance.state === 'approved' ? 'running' : 'held';
    run.stateLabel = acceptance.state === 'approved'
      ? 'Running — deploy stage unlocked'
      : 'Held — you rejected the build';
  } else if (running) {
    run.state = 'running';
    run.stateLabel = 'Running — coverage, attempt 2';
    run.elapsed = '28m 40s';
  }

  // Finished stages collapse to one-line summaries.
  const doneIds = running
    ? ['intake', 'design', 'gate.design.approval', 'freeze', 'scaffold']
    : ['intake', 'design', 'gate.design.approval', 'freeze', 'scaffold', 'coverage', 'review'];
  const done = repo.stages()
    .filter((s) => doneIds.includes(s.id))
    .map((s) => s.kind === 'human'
      ? { ...s, provenance: gates.find((g) => g.id === s.gate)?.provenance }
      : s);

  // Queued stages are ghost outlines; the acceptance decision rewrites deploy.
  const deploy = repo.stages().find((s) => s.id === 'deploy');
  const ship = gates.find((g) => g.id === 'ship.confirm');
  let next;
  if (running) {
    next = [
      { id: 'review', label: 'Review', kind: 'auto', note: 'Queued behind coverage' },
      { id: 'gate.build.acceptance', label: 'Build acceptance', kind: 'human', note: 'Your call — reachable once review is green' },
      { id: 'deploy', label: 'Deploy', kind: 'auto', note: deploy.summary },
      { id: 'ship.confirm', label: 'Ship confirm', kind: 'human', note: ship.context },
    ];
  } else {
    const deployNote = acceptance.state === 'approved'
      ? 'Unlocked by build acceptance · ship.confirm gates release'
      : acceptance.state === 'rejected'
        ? 'Held — build rejected, back to coverage with your note'
        : deploy.summary;
    next = [
      { id: 'deploy', label: 'Deploy', kind: 'auto', note: deployNote, state: acceptance.state === 'rejected' ? 'held' : decided ? 'unlocked' : 'queued' },
      { id: 'ship.confirm', label: 'Ship confirm', kind: 'human', note: ship.context, state: 'queued' },
    ];
  }

  // The ONE bright thing. A pending human gate outranks any running stage.
  let hero;
  if (running) {
    hero = {
      kind: 'stage',
      id: 'coverage', label: 'Coverage', index: 6, of: repo.stages().length,
      attempt: 2, escLimit: run.policy.escLimit,
      statusLine: 'Fix applied to the order.cart authored layer — the gate is re-running.',
      elapsed: '4m 10s', pct: 62,
      attempts: [
        { n: 1, state: 'red', note: '3 SARIF findings — kept below' },
        { n: 2, state: 'active', note: 'running now' },
      ],
    };
  } else {
    hero = {
      kind: 'gate',
      gate: acceptance,
      consequence: acceptance.state === 'approved'
        ? 'Deploy unlocked — ship.confirm still gates release.'
        : acceptance.state === 'rejected'
          ? 'Sent back to coverage with your note.'
          : null,
    };
  }

  return {
    run,
    focus: hero.kind,
    hero,
    done,
    next,
    findings: repo.findings(),
    chart: repo.chart(),
    thread: sessionData.thread ?? [],
    counts: {
      ...repo.counts(),
      gatesPending: gates.filter((g) => g.state === 'pending').length,
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

// Simulated agent replies — keyword-picked, calm, always about this run.
const REPLIES = [
  [/coverage|finding|fail|red|sarif/i,
    'Coverage went red on attempt 1 — three findings, all on order.cart: a missing viewmodel test, no mocktail coverage, and a ΔE 4.8 token drift on the frozen golden. One authored-layer fix closed all three; attempt 2 is green.'],
  [/deploy|ship|release|testflight/i,
    'Deploy is staged but locked. Build acceptance is the only thing between here and TestFlight — ship.confirm gates the release itself. Both are human gates; an agent can reach them, never pass them.'],
  [/.*/,
    'Run #47 is paused at build acceptance. Seven stages are green — coverage recovered on attempt 2 and review came back clean. The next move is yours: approve or reject in the card above.'],
];

export const postMessage = (sessionData, text) => {
  const thread = (sessionData.thread ??= []);
  const reply = REPLIES.find(([re]) => re.test(text))[1];
  thread.push({ role: 'user', text });
  thread.push({ role: 'agent', text: reply });
  return { newMessages: thread.slice(-2) };
};
