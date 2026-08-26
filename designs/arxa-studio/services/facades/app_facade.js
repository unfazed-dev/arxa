// arxa:provenance
// generator: arxa  licence: free  project: 662368770980
// Built with arxa (free tier) — https://arxa.dev
// AppFacade — composes the app-shell fixture (account, projects, gates,
// analytics, pairing) with session-scoped state (signed-in user, paired
// device, decided gates, wizard-created projects) into exactly what the
// splash / auth / pairing / dashboard viewmodels need. The locale comes
// from the request and picks the per-locale fixture, en fallback.
import * as repo from '../repositories/app_repository.js';
import * as proj from '../repositories/project_repository.js';

// ---------- session ----------
const appSlice = (sd) => (sd.app ??= { user: null, paired: null, pairError: null, decided: {}, extraProjects: [], projSeq: 0 });

// ---------- chromeless pages ----------
export const splashContext = (locale = 'en') => ({ tagline: repo.tagline(locale) });

// Startup: the loading view between splash and auth/dashboard. The step list
// is deterministic copy (daemon, kits, current project); the advance target
// is the one session-dependent bit — signed in → dashboard, else auth.
export const startupContext = (sd, translate = (key) => key, locale = 'en') => ({
  steps: [
    translate('startup.step.daemon'),
    translate('startup.step.kits'),
    translate('startup.step.project', { name: proj.currentName() ?? '—' }),
  ],
  doneThrough: 1,
  advanceHref: appSlice(sd).user ? '/dashboard' : '/auth',
});

// Auth gains two seeded lens states via ?state=, same pattern as the picker:
// signup (the sign-up pitch) and expired (session timed out — the entry
// chain's signed-out branch lands here). Both keep the seeded contract:
// any input signs in. An unknown state falls back to plain sign-in.
const AUTH_STATES = ['signup', 'expired'];

export const authContext = (locale = 'en', state) => {
  const base = repo.auth(locale);
  const lens = AUTH_STATES.includes(String(state || '').toLowerCase()) ? String(state).toLowerCase() : null;
  const variant = lens ? base.states[lens] : null;
  return {
    account: repo.account(locale),
    auth: {
      ...base,
      headline: variant?.headline ?? base.headline,
      lede: variant?.lede ?? base.lede,
      note: variant?.note ?? null,
      mode: lens ?? 'signin',
    },
  };
};

export const signIn = (sd, email, provider, locale = 'en') => {
  appSlice(sd).user = { email: email || repo.account(locale).email, via: provider || 'email' };
};

// ---------- dashboard ----------
// The project grid LIVE-READS ~/.arxa/projects (proj.listProjects → the
// server's /__projects): one card per real project, stage derived from its
// outputs, no seeded fiction. The gates strip shows only what project
// outputs contain — nothing yet (no per-project gate state files), so it
// renders its honest empty state. Stats/pairing/wizard stay seeded chrome.
export const dashboardContext = async (sd, locale = 'en') => {
  const appState = appSlice(sd);
  const { current, projects: cards } = await proj.listProjects();
  const projects = cards.map((projectCard) => ({
    id: projectCard.name,
    name: projectCard.name,
    targets: projectCard.targets,
    stage: projectCard.stage,
    stageLabel: projectCard.stage, // CSS class + the raw key; the label rides t() in the view
    detail: projectCard.flows
        ? `${projectCard.surfaces} surfaces · ${projectCard.flows} flows`
        : projectCard.surfaces
            ? `${projectCard.surfaces} surfaces`
            : '',
    current: projectCard.name === current,
  }));
  const currentCard = projects.find((projectCard) => projectCard.current) ?? projects[0] ?? null;
  return {
    account: repo.account(locale),
    user: appState.user,
    gates: [],
    gateCount: 0,
    projects,
    stats: repo.stats(locale),
    pairingModal: repo.pairing(locale),
    wizard: repo.wizard(locale),
    // Header panel project info — the shell's chrome(activeShell, prefs, project)
    // renders name + savedLabel when present.
    project: currentCard ? { name: currentCard.name, savedLabel: currentCard.detail } : null,
  };
};

// Needs-you quick actions — the strip is empty until project gate state
// exists; the endpoint stays for the shape.
export const decideGate = (sd, id, decision, locale = 'en') => {
  if (repo.gates(locale).some((gate) => gate.id === id)) appSlice(sd).decided[id] = decision;
};

// The new-project wizard: name + targets → a REAL project on disk
// (~/.arxa/projects/<name>/), 303 to intake. Names slugify to the project
// id convention; an invalid slug is a no-op (the form stays).
export const createProject = async (sd, name, targets, translate = (key) => key) => {
  const slug = String(name || '')
      .trim()
      .toLowerCase()
      .replace(/[^a-z0-9]+/g, '-')
      .replace(/^-+|-+$/g, '')
      .replace(/^([0-9])/, 'p-$1');
  if (!/^[a-z][a-z0-9]*(-[a-z0-9]+)*$/.test(slug)) return;
  const list = Array.isArray(targets) ? targets : targets ? [targets] : [];
  await proj.createProject(slug, list);
  await proj.useProject(slug);
};

// A dashboard project card picks the current project (writes ~/.arxa/current).
export const useProject = (name) => proj.useProject(name);

// The chrome macro's `project` argument for shells outside the pipeline —
// the current project's name chip, or null when none is picked.
export const chromeProject = () => {
  const name = proj.currentName();
  return name ? { name } : null;
};

// ---------- credentials ----------
// The one surface where a user manages every credential their generated app
// needs — the design-side mirror of config/credentials.catalog.json (the
// `arxa credentials` CLI holds the real values in the OS vault). The page
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
const CREDENTIAL_KEYS = new Set(CREDENTIAL_GROUPS.flatMap((group) => group.rows.map((credentialRow) => credentialRow.key)));

export const credentialsContext = (sd, translate = (key) => key) => {
  const appState = appSlice(sd);
  const held = (appState.credentials ??= {});
  const groups = CREDENTIAL_GROUPS.map((group) => ({
    id: group.id,
    label: translate(`creds.group.${group.id}`),
    rows: group.rows.map((credentialRow) => ({
      ...credentialRow,
      set: !!held[credentialRow.key],
      kindLabel: translate(`creds.kind.${credentialRow.kind}`),
      statusLabel: translate(held[credentialRow.key] ? 'creds.status.set' : 'creds.status.unset'),
      requiredLabel: translate(credentialRow.required ? 'creds.required' : 'creds.optional'),
    })),
  }));
  const missing = CREDENTIAL_GROUPS.flatMap((group) => group.rows)
    .filter((credentialRow) => credentialRow.required && !held[credentialRow.key]).length;
  return { groups, missing };
};

export const setCredential = (sd, key, value) => {
  if (CREDENTIAL_KEYS.has(key) && String(value || '').trim()) {
    (appSlice(sd).credentials ??= {})[key] = true; // held flag only — never the value
  }
};

export const unsetCredential = (sd, key) => {
  const held = (appSlice(sd).credentials ??= {});
  if (CREDENTIAL_KEYS.has(key)) delete held[key];
};

// ---------- config ----------
// The unified config surface: the design-side mirror of
// config/arxa.config.json (targets + default locale — the prototype
// persists choices in session), a compact credentials summary (the full
// editor stays at /credentials), and the chrome prefs (theme/accent/jargon,
// posted to the shared /prefs/* endpoints — no duplicate mutations here).
const CONFIG_TARGETS = ['macos', 'ios', 'android', 'web'];
const CONFIG_LOCALES = ['en', 'pl'];
import { swatchNames } from '../theme_tokens.js'; // accent set = swatch SSOT
const CONFIG_JARGONS = ['plain', 'balanced', 'technical'];

export const configContext = (sd, translate = (key) => key, prefs = {}) => {
  const appState = appSlice(sd);
  const cfg = (appState.config ??= { targets: ['macos'], defaultLocale: 'en' });
  const creds = credentialsContext(sd, translate);
  const theme = prefs.theme || 'light';
  const accent = prefs.accent || 'cyan';
  const jargon = prefs.jargon || 'balanced';
  return {
    targets: CONFIG_TARGETS.map((id) => ({ id, label: translate(`cfg.target.${id}`), on: cfg.targets.includes(id) })),
    locales: CONFIG_LOCALES.map((id) => ({ id, label: translate(`cfg.locale.${id}`), on: cfg.defaultLocale === id })),
    credGroups: creds.groups.map((group) => ({
      id: group.id,
      label: group.label,
      set: group.rows.filter((credentialRow) => credentialRow.set).length,
      total: group.rows.length,
      missing: group.rows.filter((credentialRow) => credentialRow.required && !credentialRow.set).length,
    })),
    credMissing: creds.missing,
    prefs: { theme, accent, jargon },
    accents: swatchNames().map((id) => ({ id, label: translate(`cfg.accent.${id}`), on: accent === id })),
    jargons: CONFIG_JARGONS.map((id) => ({ id, label: translate(`cfg.jargon.${id}`), on: jargon === id })),
  };
};

export const setConfig = (sd, form) => {
  const appState = appSlice(sd);
  const targets = CONFIG_TARGETS.filter((id) => form[`target_${id}`]);
  const cfg = (appState.config ??= {});
  cfg.targets = targets.length ? targets : ['macos']; // at least one target
  const locale = String(form.defaultLocale || '');
  if (CONFIG_LOCALES.includes(locale)) cfg.defaultLocale = locale;
};

// ---------- plans + mock checkout ----------
// workspace.plans — pricing + account/entitlement state, and the seeded
// checkout that walks every branch kit/payments handles. Same lens pattern as
// the scaffold picker: `?state=` picks the entitlement lens, `?pay=` picks
// the checkout outcome; an explicit lens wins over the session, and the
// session wins over the seeded default (signed-in, free).
import * as plansRepo from '../repositories/plans_repository.js';

// The seeded account session, one read for every shell that needs it (the
// scaffold picker's gate and both header chips derive from this — the app
// shell owns the session keys, so the shape lives here exactly once).
export const accountState = (sd) => {
  const appState = appSlice(sd);
  return { signedIn: !!appState.user, entitled: appState.plan === 'studio', plan: appState.plan || null };
};

const PLAN_LENSES = ['signedout', 'free', 'entitled'];

// The effective lens: explicit ?state= > session (signed-out / upgraded) >
// seeded default (free — the surface's main job is the upgrade pitch).
const planLens = (plan, state) => {
  const lens = String(state || '').toLowerCase();
  if (PLAN_LENSES.includes(lens)) return lens;
  if (!plan.user) return 'signedout';
  return plan.plan === 'studio' ? 'entitled' : 'free';
};

export const plansContext = (sd, translate = (key) => key, locale = 'en', { state, pay } = {}) => {
  const appState = appSlice(sd);
  const lens = planLens(appState, state);
  const signedOut = lens === 'signedout';
  const entitled = lens === 'entitled';
  const seedAccount = plansRepo.account(locale);

  const plans = plansRepo.plans(locale).map((plan) => ({
    ...plan,
    name: translate(`plans.plan.${plan.id}.name`),
    blurb: translate(`plans.plan.${plan.id}.blurb`),
    features: [1, 2, 3].map((featureIndex) => translate(`plans.plan.${plan.id}.feature.${featureIndex}`)),
    priceLabel: translate('plans.price', { amount: plan.monthly }),
    seatsLabel: translate('plans.seats', { count: plan.machineSeats }),
    current: entitled && plan.id === seedAccount.plan,
    // The upgrade CTA lives on the payable plan only, and only while there is
    // something to upgrade FROM. Signed-out gets the sign-in CTA instead —
    // same split as the picker's gatedNotice.
    upgradeable: !signedOut && !entitled && plan.id === plansRepo.checkout(locale).plan,
  }));

  // The mock checkout: five seeded outcomes mirroring kit/payments one-for-one
  // (the fixture carries each outcome's SeedPaymentProfile + PaymentResult
  // case). Only meaningful to a signed-in user with something to buy.
  // The active outcome is SESSION state (set by POST /checkout/attempt — the
  // Stripe test-card idiom: you pick the seeded method, the result follows);
  // ?pay= stays as the debug override. Navigation keeps the last outcome.
  const checkout = plansRepo.checkout(locale);
  const activePay = checkout.outcomes.some((outcome) => outcome.id === pay)
    ? pay
    : checkout.outcomes.some((outcome) => outcome.id === appState.checkoutOutcome)
      ? appState.checkoutOutcome
      : null;
  const checkoutCtx = {
    ...checkout,
    amountLabel: translate('plans.price', { amount: checkout.amount }),
    outcomes: checkout.outcomes.map((outcome) => ({
      ...outcome,
      label: translate(`plans.checkout.outcome.${outcome.id}.label`),
      active: outcome.id === activePay,
    })),
    active: activePay
      ? {
          id: activePay,
          ...checkout.outcomes.find((outcome) => outcome.id === activePay),
          title: translate(`plans.checkout.outcome.${activePay}.title`),
          body: translate(`plans.checkout.outcome.${activePay}.body`),
          // The retry path a PaymentDeclined branch offers: another seeded
          // attempt (the kit's own profile-flip idiom), wired as a real form
          // in the view — no href here.
          retryLabel: translate('plans.checkout.retry'),
          // Only the success branch mutates anything: applying the seeded
          // token flips the session to the paid plan. The form's action is a
          // literal in the view (the wiring selftest reads markup), so there
          // is no applyHref here.
          applyLabel: translate('plans.checkout.apply'),
        }
      : null,
  };

  return {
    state: lens,
    signedOut,
    entitled,
    user: appState.user,
    plans,
    currentPlan: entitled ? seedAccount.plan : null,
    machineSeats: entitled ? seedAccount.machineSeats : null,
    checkout: signedOut ? null : checkoutCtx,
    signInHref: '/auth',
  };
};

// A seeded checkout attempt: the user picks one of the scripted outcomes
// (the kit's SeedPaymentsProvider profiles + the plain PaymentError branch)
// and the session remembers it, so the result panel survives navigation.
// An unknown outcome is a no-op — the server never trusts the markup.
export const attemptCheckout = (sd, outcome, locale = 'en') => {
  const outcomeId = String(outcome || '').toLowerCase();
  if (plansRepo.checkout(locale).outcomes.some((candidateOutcome) => candidateOutcome.id === outcomeId)) {
    appSlice(sd).checkoutOutcome = outcomeId;
  }
};

// Sign-out flips the seeded session to signed-out (and drops the seeded
// upgrade and any scripted checkout outcome) and the route handler 303s to
// /auth — the mirror of auth's "any input signs in".
export const signOut = (sd) => {
  const appState = appSlice(sd);
  appState.user = null;
  delete appState.plan;
  delete appState.checkoutOutcome;
};

// The seeded PaymentSuccess applied: the wallet token "captured", the account
// now on the paid plan. Session state, never seed state. The outcome is
// consumed — an entitled account re-opening the checkout sees no stale panel.
export const applyUpgrade = (sd, locale = 'en') => {
  const appState = appSlice(sd);
  if (!appState.user) appState.user = { email: repo.account(locale).email, via: 'seed' };
  appState.plan = plansRepo.account(locale).plan;
  delete appState.checkoutOutcome;
};
