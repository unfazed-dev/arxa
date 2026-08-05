// appbox:provenance
// generator: appbox  licence: free  project: 662368770980
// Built with appbox (free tier) — https://appbox.dev
// Fixture generator — plans_seed.<locale>.json → plans.<locale>.json (+
// plans.json as the en alias). The seed is ids/enums/numbers only, so the
// fixture's one job is to attach the kit/payments mirror names: each checkout
// outcome carries the SeedPaymentsProvider profile and the PaymentResult case
// it resolves to (kit/payments/lib/src/providers/seed/seed_payments_provider.dart),
// so the design names exactly the branches the built app's kit layer handles.
// Never hand-edit plans*.json fixtures; edit the seed and re-run:
//   node generate.mjs
import { readFileSync, readdirSync, writeFileSync } from 'node:fs';

const dir = new URL('.', import.meta.url);
const seeds = readdirSync(dir).filter((f) => /^plans_seed\..+\.json$/.test(f));
if (!seeds.length) {
  console.error('no plans_seed.<locale>.json found');
  process.exit(66);
}

// The kit mirror, by value from seed_payments_provider.dart. `profile` is the
// SeedPaymentProfile that scripts the outcome; `result` is the PaymentResult
// case the built app's switch must handle. SeedTimeout resolves to
// PaymentError after its delay — a timeout is an error, not a fifth result.
const KIT_MIRROR = {
  succeed: { profile: 'SeedSucceed', result: 'PaymentSuccess' },
  decline: { profile: 'SeedDecline', result: 'PaymentDeclined' },
  cancel: { profile: 'SeedCancel', result: 'PaymentCancelled' },
  error: { profile: null, result: 'PaymentError' },
  timeout: { profile: 'SeedTimeout', result: 'PaymentError' },
};

for (const f of seeds.sort()) {
  const locale = f.match(/^plans_seed\.(.+)\.json$/)[1];
  const seed = JSON.parse(readFileSync(new URL(f, import.meta.url), 'utf8'));

  const checkout = {
    ...seed.checkout,
    outcomes: seed.checkout.outcomes.map((id) => ({ id, ...KIT_MIRROR[id] })),
  };

  const fixture = {
    account: seed.account,
    plans: seed.plans,
    checkout,
  };

  writeFileSync(new URL(`plans.${locale}.json`, import.meta.url), `${JSON.stringify(fixture, null, 2)}\n`);
  if (locale === 'en') {
    writeFileSync(new URL('plans.json', import.meta.url), `${JSON.stringify(fixture, null, 2)}\n`);
  }
  console.log(`plans.${locale}.json — ${seed.plans.length} plans, ${checkout.outcomes.length} checkout outcomes`);
}
