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

// ---------- embed (the viewer's app frame) ----------
// embed=1 renders the view content-only (no studio chrome — the view swaps
// its extends to _app_embed.html); qs keeps embed/vp on in-frame navigation
// (tab bar, demo cards, splash/startup meta refresh). vp is informational —
// the document adapts to the iframe size via CSS.
export const embedContext = (c) => {
  const embed = c.req.query('embed') === '1';
  const vp = c.req.query('vp') || '';
  const qs = embed ? `?embed=1${vp ? `&vp=${encodeURIComponent(vp)}` : ''}` : '';
  return { embed, vp, qs };
};

// ---------- chromeless pages ----------
export const splashContext = (locale = 'en') => ({ tagline: repo.tagline(locale) });

export const authContext = (locale = 'en') => ({ account: repo.account(locale), auth: repo.auth(locale) });

export const signIn = (sd, email, provider, locale = 'en') => {
  S(sd).user = { email: email || repo.account(locale).email, via: provider || 'email' };
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

// ---------- credentials ----------
// The one surface where a user manages every credential their generated app
// needs — the design-side mirror of config/credentials.catalog.json (the
// `appbox credentials` CLI holds the real values in the OS vault). The page
// never renders a secret back: the status chip is the only state shown.
// Simulator notes are fixture text (en), like the repository fixtures.
const CREDENTIAL_GROUPS = [
  {
    id: 'payments',
    rows: [
      { key: 'STRIPE_SECRET_KEY', kind: 'secret', required: true, url: 'https://dashboard.stripe.com/apikeys', note: 'Test keys (sk_test_…) work fully on simulators.' },
      { key: 'STRIPE_PUBLISHABLE_KEY', kind: 'publishable', required: true, url: 'https://dashboard.stripe.com/apikeys' },
      { key: 'PAYPAL_CLIENT_ID', kind: 'publishable', required: true, url: 'https://developer.paypal.com/dashboard/applications' },
      { key: 'PAYPAL_CLIENT_SECRET', kind: 'secret', required: true, url: 'https://developer.paypal.com/dashboard/applications' },
      { key: 'APPLE_PAY_MERCHANT_ID', kind: 'publishable', required: false, url: 'https://developer.apple.com/account/resources/identifiers/list/merchant', note: 'Apple Pay needs a physical device with a sandbox Apple ID — the sheet does not complete on simulators.' },
    ],
  },
  {
    id: 'auth',
    rows: [
      { key: 'APPLE_SIGN_IN_SERVICE_ID', kind: 'publishable', required: true, url: 'https://developer.apple.com/account/resources/identifiers/list/serviceId' },
      { key: 'GOOGLE_SIGN_IN_CLIENT_ID', kind: 'publishable', required: true, url: 'https://console.cloud.google.com/apis/credentials' },
      { key: 'SUPABASE_URL', kind: 'publishable', required: true, url: 'https://supabase.com/dashboard/project/_/settings/api' },
      { key: 'SUPABASE_ANON_KEY', kind: 'publishable', required: true, url: 'https://supabase.com/dashboard/project/_/settings/api' },
    ],
  },
  {
    id: 'maps',
    rows: [
      { key: 'GOOGLE_MAPS_API_KEY', kind: 'publishable', required: true, url: 'https://console.cloud.google.com/google/maps-apis/credentials' },
      { key: 'MAPBOX_PUBLIC_TOKEN', kind: 'publishable', required: true, url: 'https://console.mapbox.com/account/access-tokens/' },
      { key: 'MAPBOX_SECRET_TOKEN', kind: 'secret', required: false, url: 'https://console.mapbox.com/account/access-tokens/' },
    ],
  },
  {
    id: 'deploy',
    rows: [
      { key: 'CLOUDFLARE_API_TOKEN', kind: 'secret', required: true, url: 'https://dash.cloudflare.com/profile/api-tokens' },
      { key: 'VERCEL_TOKEN', kind: 'secret', required: true, url: 'https://vercel.com/account/tokens' },
      { key: 'APP_STORE_CONNECT_PRIVATE_KEY', kind: 'secret', required: true, url: 'https://appstoreconnect.apple.com/access/integrations/api' },
      { key: 'SHOREBIRD_TOKEN', kind: 'secret', required: false, url: 'https://console.shorebird.dev/', note: 'Only needed for CI — local `shorebird release` uses the CLI login.' },
    ],
  },
  {
    id: 'llm',
    rows: [
      { key: 'KIMI_API_KEY', kind: 'secret', required: false, url: 'https://platform.moonshot.ai/console/api-keys' },
      { key: 'ANTHROPIC_API_KEY', kind: 'secret', required: false, url: 'https://console.anthropic.com/settings/keys' },
      { key: 'OPENAI_API_KEY', kind: 'secret', required: false, url: 'https://platform.openai.com/api-keys' },
      { key: 'GEMINI_API_KEY', kind: 'secret', required: false, url: 'https://aistudio.google.com/apikey' },
    ],
  },
];
const CREDENTIAL_KEYS = new Set(CREDENTIAL_GROUPS.flatMap((g) => g.rows.map((r) => r.key)));

export const credentialsContext = (sd, t = (k) => k) => {
  const s = S(sd);
  const held = (s.credentials ??= {});
  const groups = CREDENTIAL_GROUPS.map((g) => ({
    id: g.id,
    label: t(`creds.group.${g.id}`),
    rows: g.rows.map((r) => ({
      ...r,
      set: !!held[r.key],
      kindLabel: t(`creds.kind.${r.kind}`),
      statusLabel: t(held[r.key] ? 'creds.status.set' : 'creds.status.unset'),
      requiredLabel: t(r.required ? 'creds.required' : 'creds.optional'),
    })),
  }));
  const missing = CREDENTIAL_GROUPS.flatMap((g) => g.rows)
    .filter((r) => r.required && !held[r.key]).length;
  return { groups, missing };
};

export const setCredential = (sd, key, value) => {
  if (CREDENTIAL_KEYS.has(key) && String(value || '').trim()) {
    (S(sd).credentials ??= {})[key] = true; // held flag only — never the value
  }
};

export const unsetCredential = (sd, key) => {
  const held = (S(sd).credentials ??= {});
  if (CREDENTIAL_KEYS.has(key)) delete held[key];
};

// ---------- config ----------
// The unified config surface: the design-side mirror of
// config/appbox.config.json (targets + default locale — the prototype
// persists choices in session), a compact credentials summary (the full
// editor stays at /credentials), and the chrome prefs (theme/accent/jargon,
// posted to the shared /prefs/* endpoints — no duplicate mutations here).
const CONFIG_TARGETS = ['macos', 'ios', 'android', 'web'];
const CONFIG_LOCALES = ['en', 'pl'];
const CONFIG_ACCENTS = ['cyan', 'violet', 'blue', 'ember'];
const CONFIG_JARGONS = ['plain', 'balanced', 'technical'];

export const configContext = (sd, t = (k) => k, prefs = {}) => {
  const s = S(sd);
  const cfg = (s.config ??= { targets: ['macos'], defaultLocale: 'en' });
  const creds = credentialsContext(sd, t);
  const theme = prefs.theme || 'light';
  const accent = prefs.accent || 'cyan';
  const jargon = prefs.jargon || 'balanced';
  return {
    targets: CONFIG_TARGETS.map((id) => ({ id, label: t(`cfg.target.${id}`), on: cfg.targets.includes(id) })),
    locales: CONFIG_LOCALES.map((id) => ({ id, label: t(`cfg.locale.${id}`), on: cfg.defaultLocale === id })),
    credGroups: creds.groups.map((g) => ({
      id: g.id,
      label: g.label,
      set: g.rows.filter((r) => r.set).length,
      total: g.rows.length,
      missing: g.rows.filter((r) => r.required && !r.set).length,
    })),
    credMissing: creds.missing,
    prefs: { theme, accent, jargon },
    accents: CONFIG_ACCENTS.map((id) => ({ id, label: t(`cfg.accent.${id}`), on: accent === id })),
    jargons: CONFIG_JARGONS.map((id) => ({ id, label: t(`cfg.jargon.${id}`), on: jargon === id })),
  };
};

export const setConfig = (sd, form) => {
  const s = S(sd);
  const targets = CONFIG_TARGETS.filter((id) => form[`target_${id}`]);
  const cfg = (s.config ??= {});
  cfg.targets = targets.length ? targets : ['macos']; // at least one target
  const locale = String(form.defaultLocale || '');
  if (CONFIG_LOCALES.includes(locale)) cfg.defaultLocale = locale;
};
