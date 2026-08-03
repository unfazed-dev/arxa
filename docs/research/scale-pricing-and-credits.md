# SCALE pricing, managed-kit resale, and LLM credits

## Summary (≤150 words)

Comparables for "we operate your mobile apps in the stores + OTA" cluster at
**$99–$299/mo per org**, not per seat: Bitrise Starter $99 / Pro $218, Expo EAS
Production $199, Codemagic Professional $299. Only FlutterFlow charges per seat
($150 first seat + $85/seat) and that is the market's loudest complaint.
Recommend **SCALE at $149/mo per org, unlimited seats, 3 released apps, then
$49/app/mo** — priced on the *app fleet* axis, because OTA metering cannot carry
the tier: Shorebird's $1/2,500 installs is **$0.0004/install**, so a 10k-install
month is $4 of raw cost. Pass installs through at **$1.50/2,500 (1.5×)** after a
bundled 50k.

Managed Supabase is viable via **Supabase for Platforms** (projects in *our*
org), whose price is ~$10–25/project — resell at ~$39 (≈30% take, the Heroku
precedent). Escape hatch: OAuth `project-claim`. Credits should follow Cursor:
BYO-LLM keeps **full parity**; credits buy convenience + the appbox fine-tune.

---

## Q1 — SCALE price point

### Comparable set (2026 figures)

| Product | Shape | Price |
|---|---|---|
| **Shorebird** (OTA only) | platform fee + metered installs | Free 5,000 installs; **Pro ~$20/mo incl. 50,000 patch installs**; overage **$1 per 2,500 installs**; higher tier 1,000,000; Enterprise custom ([pricing](https://shorebird.dev/pricing), [billing docs](https://docs.shorebird.dev/account/billing/)) |
| **Expo EAS** | plan + usage | Starter $19; **Production $199/mo** (50k MAU, 1 TiB bandwidth, $225 build credit, 2 concurrency); Enterprise custom (1M+ MAU) ([docs.expo.dev/billing/plans](https://docs.expo.dev/billing/plans/)) |
| **Codemagic** | per-minute or flat | PAYG **$10/user/mo** + $0.095/min macOS premium; **Professional $299/mo** unlimited users + unlimited minutes + 3 concurrency; +$100/mo per extra concurrency; $3,990/yr annual ([codemagic.io/pricing](https://codemagic.io/pricing/)) |
| **Bitrise** | flat + concurrency | **Starter $99/mo** (3 concurrency, ≤10 users); **Pro $218/mo** (10 macOS concurrency, unlimited members); Velocity ~$2,500/mo ([bitrise.io/pricing](https://bitrise.io/pricing)) |
| **Ionic Appflow** | **dead** | New sales ended 2025-02-11, full shutdown 2027-12-31 (OutSystems). Historic Launch $49/mo; Scale had 5 seats + 5,000 Live-Update MAUs ([capawesome.io alternatives](https://capawesome.io/alternatives/ionic-appflow/)) |
| **Capawesome Cloud** (Appflow successor) | flat, no seats | Live Updates **from $9/mo**; full platform w/ cloud builds **from $19/mo**, unlimited live updates, no per-seat fee ([capawesome.io](https://capawesome.io/blog/alternative-to-appflow/)) |
| **FlutterFlow** | **per seat** | Basic $39; Growth $80 first seat + $55 second; **Business $150 first seat + $85/seat (2–5)**; Enterprise custom ([docs.flutterflow.io](https://docs.flutterflow.io/accounts-billing/plan-pricing/)) — supersedes the stale numbers in `competitors-and-pricing.md` |

### The arithmetic that decides the axis

Shorebird overage is **$1 / 2,500 installs = $0.0004 per patch install**.

| Monthly patch installs | Raw Shorebird cost |
|---|---|
| 10,000 | $4.00 |
| 50,000 | $20.00 (bundled in Pro) |
| 250,000 | $100.00 |
| 1,000,000 | $400.00 |

**OTA metering cannot carry SCALE.** Below ~250k installs/mo it is a rounding
error against a $149 subscription. The tier's price must rest on the durable
work — store releases, signing identities, fleet management, custom domains —
with installs as a pass-through line item, not the revenue engine.

### The axis: per-app, not per-seat

Comparables split cleanly by what they actually consume: CI prices on
**concurrency** (Codemagic, Bitrise), OTA prices on **installs/MAU** (Shorebird,
Expo, Capawesome), visual builders price on **seats** (FlutterFlow). appbox
SCALE consumes store slots and release pipelines — an *app-fleet* cost. Prior
repo research (`competitors-and-pricing.md`) records per-seat as the market's
loudest complaint, with agencies as persona P5; agencies have few seats and many
apps. Per-seat SCALE would contradict our own positioning.

### Recommendation

**SCALE: $149/mo per organization — unlimited seats, 3 released apps, 50,000
bundled patch installs across the fleet.**

- **+$49/app/mo** beyond 3 apps.
- **Patch installs beyond 50k: $1.50 per 2,500 (= $0.0006/install), a 1.5× pass-through** on Shorebird's $1/2,500. Overage **off by default** with a console spend cap, mirroring Shorebird's own default — bill shock is a named FlutterFlow/Firebase grievance we are positioned against.
- **Defensible band: $99–$249/mo.** $99 = Bitrise Starter floor; $249 sits under Expo Production+usage and Codemagic $299 while including OTA that neither bundles. Anchor at $149.
- Enterprise (SAML, audit logs, invoice billing, dedicated fleet) → custom, matching Shorebird's and Expo's top tiers.

---

## Q2 — Reselling managed kit (Supabase et al.)

### Can appbox provision Supabase per customer? Yes — two shapes.

**Supabase for Platforms** — Supabase is explicitly a PaaS "commonly used as a
platform by AI Builders," managed via the **Management API** (`POST /v1/projects`,
`GET /v1/projects/available-regions`, `GET /v1/projects/{ref}/health`) with
projects living **in an organization we own**
([docs](https://supabase.com/docs/guides/integrations/supabase-for-platforms)).
Lovable, Bolt, and Baidu MeDo are cited as users of this path.

**OAuth integration** — projects live in the **customer's own org**
([docs](https://supabase.com/docs/guides/integrations/build-a-supabase-oauth-integration)).
Critically there is a **`project-claim`** OAuth endpoint
(`/v1/oauth/authorize/project-claim`) that transfers a project we created into
the customer's org — the escape hatch that keeps appbox's no-lock-in promise
intact while still offering a managed default.

There is also a formal **Integration Partner Addendum** and partner program
([supabase.com/partners](https://supabase.com/partners/integrations)).

**Underlying cost:** Supabase Pro is **$25/mo for the first project, additional
projects from $10/mo**, with $10/mo compute credits covering one Micro instance;
Team $599/mo; usage beyond that at $0.00325/MAU, $0.09/GB egress
([supabase.com/pricing](https://supabase.com/pricing)).

### Precedent for the billing shape

| Precedent | Shape | Economics |
|---|---|---|
| **Heroku Add-ons** | Heroku is merchant of record, provider gets a revenue share | **70/30 split** — "Heroku shall pay Provider 70% of the Net Subscription Revenues," changeable on 30 days' notice ([Add-ons License & Distribution Agreement, PDF](https://addons.heroku.com/provider/resources/HerokuAddonsLicenseAgreement.pdf)) |
| **Vercel Marketplace** (Neon, Upstash, Supabase) | Native integration: auto-provisioning, credentials injected as env vars, **unified billing through Vercel** as merchant of record, console access retained ([docs](https://vercel.com/docs/marketplace-storage), [program](https://vercel.com/marketplace/program)) | **Same price as going direct.** Vercel/provider split is **not disclosed** in any public source — do not infer a percentage |

**The standard shape is therefore: same-price-as-direct to the customer, margin
taken from the provider side (~30% is the only hard published number), unified
billing, no per-resource markup on the invoice.** Retail markup on top of list
price is *not* the market convention and would be visible and resented.

### Known failure modes (all attach to the *our-org* path)

1. **Pooled-org liability** — every customer project sits under one appbox org: one payment failure, one ToS violation, or one Supabase-side suspension is fleet-wide. Compute, egress and MAU overages land on *our* card first.
2. **Abuse surface** — we hold the personal access token that can create projects; a compromised or abusive tenant spends our money at $0.09/GB egress.
3. **Free-tier arbitrage** — Supabase Free allows only **2 active projects per org** and pauses after 1 week idle, so a "free managed DB" cannot be pooled; anyone building one on our org is spending our Pro allowance.
4. **Password custody** — project DB passwords cannot be rotated programmatically after creation (Supabase's own warning); we become the custodian of secrets we cannot rotate.

### Recommendation

**Managed Kit = a SCALE add-on at $39/project/mo (cost $10–25), billed through
appbox as merchant of record, with a one-click `project-claim` handover to the
customer's own Supabase org at any time.** BYO-Supabase stays free on every
tier. Cap egress/MAU per project with hard spend limits, and require a card on
file for the add-on specifically — never pool a free tenant into the org.

---

## Q3 — LLM credits economics

### How the market prices credits vs BYO-key

| Product | Credit shape | BYO-key |
|---|---|---|
| **Cursor** | Pro $20/mo includes a **$20 credit pool**; **Auto mode is unlimited and does not draw the pool**; manually selected frontier models draw it; overage billed **at API rates with "no penalty markup"**. Pro+ $60, Ultra $200, Teams $40/user, Teams Premium $120/user ([cursor.com/help](https://cursor.com/help/models-and-usage/api-keys)) | Supported for OpenAI/Anthropic/Google/Azure/Bedrock, **works even on the free tier**. But Tab and Apply-from-Chat run on Cursor's *own* models and cannot be billed to your key |
| **Lovable** | Credit balance + daily grants. Credits are **not equal in value across plans**; Default Mode varies by task complexity (0.5–1.7 credits/message), Plan Mode 1/message. **Monthly credits expire after 2 months; daily grants don't roll over**; top-ups last 12 months ([lovable.dev/pricing](https://lovable.dev/pricing)) | None |
| **Bolt / v0** | Token- or credit-metered subscriptions from ~$20/mo with top-ups | v0 ships via Vercel Marketplace integrations; no first-class BYO-key |

**Margin observation:** the leaders are converging on *near-zero markup on
inference itself*. Cursor explicitly bills overage at API rates. Margin comes
from (a) the subscription's fixed fee, (b) routing cheap models under "Auto"
while charging a flat pooled rate, and (c) breakage — Lovable's 2-month expiry
and non-rolling daily grants. **(c) is the mechanic that generates the
complaints**; treat it as a thing to avoid, not copy.

**Gating pattern:** nobody gives BYO-key users *worse generation*. Cursor gates
only the proprietary bits it cannot bill to your key (Tab, Apply). That is the
principled line — gate on *what the vendor owns*, not on *how you pay*.

### Recommendation for appbox

**BYO-LLM keeps full parity on every generation feature, on every tier,
forever.** It is our structural cost advantage, not a downgrade path.

Credits sell three things BYO-LLM cannot supply:

1. **Zero-config onboarding** — no key, works in 30 seconds.
2. **The appbox fine-tune** — appbox-owned weights, so credit-gating it gates *our asset*, not a payment method. This is the Cursor-Tab line.
3. **Fleet/CI inference** — server-side generation in deploy pipelines where the user's key is not present.

Shape: **monthly pool at face value** ($20 of credits inside the $20 PRO seat,
Cursor-style), **overage at raw API cost + 15%** — disclosed, capped, off by
default. **Prepaid top-ups do not expire.** Monthly pool rolls over one cycle.
No per-plan credit revaluation, no daily-grant games.

---

## Verification notes

- Shorebird's per-tier **dollar prices** are not on the fetched `shorebird.dev/pricing` HTML (feature/quota table only); the **$20/mo Pro incl. 50,000 installs** figure is aggregator/blog-sourced — **not first-party verified**. The **$1/2,500 overage** *is* on the first-party pricing table.
- Vercel↔provider revenue split: **undisclosed**, not estimated here.
- Bitrise and Codemagic tier names have churned; figures above are 2026 reports and should be re-checked before a public price page ships.
- `docs/research/competitors-and-pricing.md` carries **stale FlutterFlow numbers** ($30–39 / $70 / $150). Current is Basic $39 / Growth $80+$55 / Business $150+$85. Not edited here — flagged for the owner of that file.
