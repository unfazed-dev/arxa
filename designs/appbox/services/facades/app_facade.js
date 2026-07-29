// AppFacade — composes the app-shell fixture (account, projects, gates,
// analytics, pairing) with session-scoped state (signed-in user, paired
// device, decided gates, wizard-created projects) into exactly what the
// splash / auth / pairing / dashboard viewmodels need.
import * as repo from '../repositories/app_repository.js';

// ---------- session ----------
const S = (sd) => (sd.app ??= { user: null, paired: null, pairError: null, decided: {}, extraProjects: [], projSeq: 0 });

// ---------- chromeless pages ----------
export const splashContext = () => ({ tagline: repo.tagline() });

export const authContext = () => ({ account: repo.account(), auth: repo.auth() });

export const signIn = (sd, email, provider) => {
  S(sd).user = { email: email || repo.account().email, via: provider || 'email' };
};

export const pairingContext = (sd) => {
  const s = S(sd);
  const p = repo.pairing();
  return {
    paired: s.paired,
    pairError: s.pairError,
    host: p.fingerprint,
  };
};

// One-scan pairing: the code from the desktop QR, single-use. A wrong code
// re-renders the form with the error; a right code pairs and 303s back.
export const confirmPairing = (sd, code) => {
  const s = S(sd);
  const ok = String(code || '').trim().toUpperCase() === repo.pairing().code.toUpperCase();
  s.pairError = ok ? null : 'That code doesn’t match — check the QR on the desktop and try again.';
  if (ok) s.paired = { deviceName: repo.pairing().deviceName, at: 'paired just now' };
  return ok;
};

// ---------- dashboard ----------
export const dashboardContext = (sd) => {
  const s = S(sd);
  const gates = repo.gates().filter((g) => !s.decided[g.id]);
  const projects = [...repo.projects(), ...s.extraProjects];
  const current = projects[0];
  return {
    account: repo.account(),
    user: s.user,
    gates,
    gateCount: gates.length,
    projects,
    stats: repo.stats(),
    pairingModal: repo.pairing(),
    wizard: repo.wizard(),
    // Appbar project info — the shell's shellNav(activeTab, prefs, project)
    // renders name + savedLabel when present.
    project: { name: current.name, savedLabel: current.lastSaved },
  };
};

// Needs-you quick actions — seeded: the gate leaves the strip, 303 back.
export const decideGate = (sd, id, decision) => {
  if (repo.gates().some((g) => g.id === id)) S(sd).decided[id] = decision;
};

// GenUI new-project wizard: name + targets → a seeded project row, 303 to intake.
export const createProject = (sd, name, targets) => {
  const s = S(sd);
  const seq = (s.projSeq += 1);
  const list = Array.isArray(targets) ? targets : targets ? [targets] : [];
  s.extraProjects.push({
    id: `p-new-${seq}`,
    name: String(name || '').trim() || `Untitled project ${seq}`,
    targets: list.length ? list : ['web'],
    stage: 'intake',
    stageLabel: 'Intake · interview',
    lastSaved: 'saved just now',
  });
};
