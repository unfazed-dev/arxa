// appbox:provenance
// generator: appbox  licence: free  project: 662368770980
// Built with appbox (free tier) — https://appbox.dev
// AppFacade — composes the app-shell fixture (account, projects, gates,
// analytics, pairing) with session-scoped state (signed-in user, paired
// device, decided gates, wizard-created projects) into exactly what the
// splash / auth / pairing / dashboard viewmodels need. The locale comes
// from the request and picks the per-locale fixture, en fallback.
import * as repo from '../repositories/app_repository.js';

// Catalog lookup with the former en literal as fallback while a key awaits
// merge into l10n/app_*.arb (same pattern as screens_facade.labelOf).
const tr = (t, key, vars, fallback) => {
  const v = t(key, vars);
  return v == key ? fallback : v;
};

// ---------- session ----------
const S = (sd) => (sd.app ??= { user: null, paired: null, pairError: null, decided: {}, extraProjects: [], projSeq: 0 });

// ---------- chromeless pages ----------
export const splashContext = (locale = 'en') => ({ tagline: repo.tagline(locale) });

export const authContext = (locale = 'en') => ({ account: repo.account(locale), auth: repo.auth(locale) });

export const signIn = (sd, email, provider, locale = 'en') => {
  S(sd).user = { email: email || repo.account(locale).email, via: provider || 'email' };
};

export const pairingContext = (sd, locale = 'en') => {
  const s = S(sd);
  const p = repo.pairing(locale);
  return {
    paired: s.paired,
    pairError: s.pairError,
    host: p.fingerprint,
  };
};

// One-scan pairing: the code from the desktop QR, single-use. A wrong code
// re-renders the form with the error; a right code pairs and 303s back.
export const confirmPairing = (sd, code, locale = 'en', t = (k) => k) => {
  const s = S(sd);
  const ok = String(code || '').trim().toUpperCase() === repo.pairing(locale).code.toUpperCase();
  s.pairError = ok ? null : tr(t, 'pair.errorMismatch', null, 'That code doesn’t match — check the QR on the desktop and try again.');
  if (ok) s.paired = { deviceName: repo.pairing(locale).deviceName, at: tr(t, 'pair.justNow', null, 'paired just now') };
  return ok;
};

// ---------- dashboard ----------
export const dashboardContext = (sd, locale = 'en') => {
  const s = S(sd);
  const gates = repo.gates(locale).filter((g) => !s.decided[g.id]);
  const projects = [...repo.projects(locale), ...s.extraProjects];
  const current = projects[0];
  return {
    account: repo.account(locale),
    user: s.user,
    gates,
    gateCount: gates.length,
    projects,
    stats: repo.stats(locale),
    pairingModal: repo.pairing(locale),
    wizard: repo.wizard(locale),
    // Header panel project info — the shell's chrome(activeShell, prefs, project)
    // renders name + savedLabel when present.
    project: { name: current.name, savedLabel: current.lastSaved },
  };
};

// Needs-you quick actions — seeded: the gate leaves the strip, 303 back.
export const decideGate = (sd, id, decision, locale = 'en') => {
  if (repo.gates(locale).some((g) => g.id === id)) S(sd).decided[id] = decision;
};

// GenUI new-project wizard: name + targets → a seeded project row, 303 to intake.
export const createProject = (sd, name, targets, t = (k) => k) => {
  const s = S(sd);
  const seq = (s.projSeq += 1);
  const list = Array.isArray(targets) ? targets : targets ? [targets] : [];
  s.extraProjects.push({
    id: `p-new-${seq}`,
    name: String(name || '').trim() || tr(t, 'dash.untitledProject', { n: seq }, `Untitled project ${seq}`),
    targets: list.length ? list : ['web'],
    stage: 'intake',
    stageLabel: tr(t, 'dash.stageIntake', null, 'Intake · interview'),
    lastSaved: tr(t, 'dash.savedJustNow', null, 'saved just now'),
  });
};
