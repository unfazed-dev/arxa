// appbox:provenance
// generator: appbox  licence: free  project: 662368770980
// Built with appbox (free tier) — https://appbox.dev
// AppFacade — composes the app-shell fixture (account, projects, gates,
// analytics, pairing) with session-scoped state (signed-in user, paired
// device, decided gates, wizard-created projects) into exactly what the
// splash / auth / pairing / dashboard viewmodels need. The locale comes
// from the request and picks the per-locale fixture, en fallback.
import * as repo from '../repositories/app_repository.js';
import * as proj from '../repositories/project_repository.js';

// ---------- session ----------
const S = (sd) => (sd.app ??= { user: null, paired: null, pairError: null, decided: {}, extraProjects: [], projSeq: 0 });

// ---------- chromeless pages ----------
export const splashContext = (locale = 'en') => ({ tagline: repo.tagline(locale) });

// Startup: the loading view between splash and auth/dashboard. The step list
// is deterministic copy (daemon, kits, current project); the advance target
// is the one session-dependent bit — signed in → dashboard, else auth.
export const startupContext = (sd, t = (k) => k, locale = 'en') => ({
  steps: [
    t('startup.step.daemon'),
    t('startup.step.kits'),
    t('startup.step.project', { name: proj.currentName() ?? '—' }),
  ],
  doneThrough: 1,
  advanceHref: S(sd).user ? '/dashboard' : '/auth',
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
  S(sd).user = { email: email || repo.account(locale).email, via: provider || 'email' };
};

// ---------- dashboard ----------
// The project grid LIVE-READS ~/.appbox/projects (proj.listProjects → the
// server's /__projects): one card per real project, stage derived from its
// outputs, no seeded fiction. The gates strip shows only what project
// outputs contain — nothing yet (no per-project gate state files), so it
// renders its honest empty state. Stats/pairing/wizard stay seeded chrome.
export const dashboardContext = async (sd, locale = 'en') => {
  const s = S(sd);
  const { current, projects: cards } = await proj.listProjects();
  const projects = cards.map((p) => ({
    id: p.name,
    name: p.name,
    targets: p.targets,
    stage: p.stage,
    stageLabel: p.stage, // CSS class + the raw key; the label rides t() in the view
    detail: p.flows
        ? `${p.surfaces} surfaces · ${p.flows} flows`
        : p.surfaces
            ? `${p.surfaces} surfaces`
            : '',
    current: p.name === current,
  }));
  const currentCard = projects.find((p) => p.current) ?? projects[0] ?? null;
  return {
    account: repo.account(locale),
    user: s.user,
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
  if (repo.gates(locale).some((g) => g.id === id)) S(sd).decided[id] = decision;
};

// The new-project wizard: name + targets → a REAL project on disk
// (~/.appbox/projects/<name>/), 303 to intake. Names slugify to the project
// id convention; an invalid slug is a no-op (the form stays).
export const createProject = async (sd, name, targets, t = (k) => k) => {
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

// A dashboard project card picks the current project (writes ~/.appbox/current).
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
import { swatchNames } from '../theme_tokens.js'; // accent set = swatch SSOT
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
    accents: swatchNames().map((id) => ({ id, label: t(`cfg.accent.${id}`), on: accent === id })),
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
  const s = S(sd);
  return { signedIn: !!s.user, entitled: s.plan === 'studio', plan: s.plan || null };
};

const PLAN_LENSES = ['signedout', 'free', 'entitled'];

// The effective lens: explicit ?state= > session (signed-out / upgraded) >
// seeded default (free — the surface's main job is the upgrade pitch).
const planLens = (s, state) => {
  const lens = String(state || '').toLowerCase();
  if (PLAN_LENSES.includes(lens)) return lens;
  if (!s.user) return 'signedout';
  return s.plan === 'studio' ? 'entitled' : 'free';
};

export const plansContext = (sd, t = (k) => k, locale = 'en', { state, pay } = {}) => {
  const s = S(sd);
  const lens = planLens(s, state);
  const signedOut = lens === 'signedout';
  const entitled = lens === 'entitled';
  const seedAccount = plansRepo.account(locale);

  const plans = plansRepo.plans(locale).map((p) => ({
    ...p,
    name: t(`plans.plan.${p.id}.name`),
    blurb: t(`plans.plan.${p.id}.blurb`),
    features: [1, 2, 3].map((i) => t(`plans.plan.${p.id}.feature.${i}`)),
    priceLabel: t('plans.price', { amount: p.monthly }),
    seatsLabel: t('plans.seats', { count: p.machineSeats }),
    current: entitled && p.id === seedAccount.plan,
    // The upgrade CTA lives on the payable plan only, and only while there is
    // something to upgrade FROM. Signed-out gets the sign-in CTA instead —
    // same split as the picker's gatedNotice.
    upgradeable: !signedOut && !entitled && p.id === plansRepo.checkout(locale).plan,
  }));

  // The mock checkout: five seeded outcomes mirroring kit/payments one-for-one
  // (the fixture carries each outcome's SeedPaymentProfile + PaymentResult
  // case). Only meaningful to a signed-in user with something to buy.
  // The active outcome is SESSION state (set by POST /checkout/attempt — the
  // Stripe test-card idiom: you pick the seeded method, the result follows);
  // ?pay= stays as the debug override. Navigation keeps the last outcome.
  const checkout = plansRepo.checkout(locale);
  const activePay = checkout.outcomes.some((o) => o.id === pay)
    ? pay
    : checkout.outcomes.some((o) => o.id === s.checkoutOutcome)
      ? s.checkoutOutcome
      : null;
  const checkoutCtx = {
    ...checkout,
    amountLabel: t('plans.price', { amount: checkout.amount }),
    outcomes: checkout.outcomes.map((o) => ({
      ...o,
      label: t(`plans.checkout.outcome.${o.id}.label`),
      active: o.id === activePay,
    })),
    active: activePay
      ? {
          id: activePay,
          ...checkout.outcomes.find((o) => o.id === activePay),
          title: t(`plans.checkout.outcome.${activePay}.title`),
          body: t(`plans.checkout.outcome.${activePay}.body`),
          // The retry path a PaymentDeclined branch offers: another seeded
          // attempt (the kit's own profile-flip idiom), wired as a real form
          // in the view — no href here.
          retryLabel: t('plans.checkout.retry'),
          // Only the success branch mutates anything: applying the seeded
          // token flips the session to the paid plan. The form's action is a
          // literal in the view (the wiring selftest reads markup), so there
          // is no applyHref here.
          applyLabel: t('plans.checkout.apply'),
        }
      : null,
  };

  return {
    state: lens,
    signedOut,
    entitled,
    user: s.user,
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
  const o = String(outcome || '').toLowerCase();
  if (plansRepo.checkout(locale).outcomes.some((x) => x.id === o)) {
    S(sd).checkoutOutcome = o;
  }
};

// Sign-out flips the seeded session to signed-out (and drops the seeded
// upgrade and any scripted checkout outcome) and the route handler 303s to
// /auth — the mirror of auth's "any input signs in".
export const signOut = (sd) => {
  const s = S(sd);
  s.user = null;
  delete s.plan;
  delete s.checkoutOutcome;
};

// The seeded PaymentSuccess applied: the wallet token "captured", the account
// now on the paid plan. Session state, never seed state. The outcome is
// consumed — an entitled account re-opening the checkout sees no stale panel.
export const applyUpgrade = (sd, locale = 'en') => {
  const s = S(sd);
  if (!s.user) s.user = { email: repo.account(locale).email, via: 'seed' };
  s.plan = plansRepo.account(locale).plan;
  delete s.checkoutOutcome;
};
