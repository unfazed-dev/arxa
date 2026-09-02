# Pricing unit: per-seat vs per-org flat vs usage vs hybrid

Research date: 2026-09-02. Every factual claim carries its source URL. Prices are
as read on the vendor page on that date; where a page could not be read it is
marked UNREADABLE rather than guessed.

## 1. Verdict

- **Pro = per-seat, ~$20–40/seat/mo.** Keep it. Scaffold access is consumed by a
  person; seats are the value unit and D104 already says this.
- **Scale = per-org flat + per-app + install overage.** Keep D30 exactly:
  $149/mo/org, unlimited seats, 3 apps, +$49/app, 50k installs, $1.50/2,500 over.
- **Agency = per-seat, org owner buys quantity.** Keep D102.
- **Agency is NOT the Scale tier.** They are separate SKUs on separate value
  axes, and both decisions are internally correct.
- Reasoning: the billing unit should track the value driver, not the tier ladder.
  Scale sells *app-fleet volume* — released apps and OTA installs are the things
  that grow and the only things that cost arxa money, so seats are the wrong
  lever and per-seat there would contradict the anti-FlutterFlow position. Agency
  sells *per-person access to business/admin sections* — HR, accounting, client
  folders — where a 12-person agency genuinely gets ~12x the value of a
  freelancer, so a flat per-company price has no expansion lever at all. D30's
  "NEVER per-seat" is scoped to the app-output ladder; it was never a company-wide
  ban. Sell both, price each on its own axis.

## 2. Industry data

- Kyle Poyar polled 230 B2B software and AI companies for the 2026 report: 37%
  now run **hybrid** pricing (two or more models combined, e.g. per-seat plus
  consumption) — the single most popular model. Hybrid was 25% twelve months
  earlier, so 25% → 37% in a year
  (https://www.growthunhinged.com/p/the-state-of-b2b-monetization-in-2026).
- Same report: **early-stage companies under $5M ARR gravitate to flat fees (37%
  adoption)** — the highest flat-fee share of any cohort — while companies over
  $150M ARR hold legacy per-seat (29%). arxa is in the first cohort
  (https://www.growthunhinged.com/p/the-state-of-b2b-monetization-in-2026).
- Same report, investor preference: only 10% named flat-fee and 5% named
  seat-based as the model investors want; 35% hybrid, 26% outcome, 24% usage.
  Note this is what *investors* prefer, not what customers buy
  (https://www.growthunhinged.com/p/the-state-of-b2b-monetization-in-2026).
- Poyar's 2025 report (240 companies) gives the prior year's movement: flat-fee
  29% → 22%, seat-based 21% → 15%, hybrid 27% → 41%
  (https://www.growthunhinged.com/p/2025-state-of-b2b-monetization).
- Outcome-based pricing is aspiration, not practice: 5% of 2025 respondents had
  it as their primary model, though 25% expected to by 2028
  (https://www.growthunhinged.com/p/2025-state-of-b2b-monetization).
- Metronome + Greyhound Capital surveyed 100 SaaS companies (Jan 2025): 85% have
  adopted usage-based pricing in some form, 77% of the largest software
  companies, 64% of Forbes' next billion-dollar startups. Note "some level of
  UBP" is a loose bar — it includes a single metered line on a subscription
  (https://metronome.com/state-of-usage-based-pricing).
- **The counter-trend is real and it matters more for arxa than the headline.**
  In December 2025 Marc Benioff said seat-based pricing was becoming the norm for
  Salesforce's AI agents, after the company had flirted with consumption and
  per-conversation pricing — the driver was customers demanding predictability
  (https://www.theregister.com/software/2025/12/12/salesforce-opts-for-seat-based-ai-licensing/).
- Cursor's own post-mortem on its June 2025 pricing change: "Our users love per
  seat pricing. It's just the cost side makes it harder." The move from unlimited
  usage to tiered consumption limits produced a public apology and user churn
  (https://www.saastr.com/cursor-our-users-love-per-seat-pricing-its-just-the-cost-side-makes-it-harder/).
  **arxa does not have Cursor's cost side** — BYO-LLM keys, engine on the
  customer's machine, marginal cost per user ~zero. The single reason Cursor had
  to abandon flat/seat pricing does not apply here.
- Metronome's 2025 field research on AI monetization found customer anxiety about
  unpredictable cost is the number one barrier to adoption — "usage stopped not
  because of price, but because admins didn't trust they'd stay in budget";
  enterprise buyers push back on AI line items unless flat-rate or capped
  (https://metronome.com/blog/the-state-of-ai-monetization-field-research).
- Gartner's agentic-arbitrage estimate (cited secondhand via a vendor blog, not
  read from Gartner directly): up to $234B of enterprise application software
  spend, ~20% of the market, structurally at risk by 2030, with ≥40% of
  enterprise SaaS spend moving to usage-, agent- or outcome-based pricing by 2030
  (secondhand via https://crewdle.com/blog/the-end-of-per-seat-pricing).

**Read of the data:** the shift away from *pure* per-seat is well documented, but
it is driven by AI COGS and by seat compression in tools where an agent replaces
a human user. Neither applies to arxa's Agency SKU, which sells desk access to
business software that humans operate. The applicable lesson is the hybrid one:
seats where a person consumes value, volume meters where the fleet does.

## 3. Comparables

| Product | Unit | Current price | What the unit buys | Notes |
|---|---|---|---|---|
| FlutterFlow | Per seat, banded by team size | Business tier + **$85/seat/mo above 5 seats** (transitional, Sept 2025–Sept 2026) | One editor seat in a team | Aug 2025 repricing moved to team-size bands; non-paid collaborators drop to view-only (https://docs.flutterflow.io/accounts-billing/plan-pricing/) |
| Figma | Per seat, **4 seat types** | Full / Dev / Collab / View seats, priced per tier | Product access by role; View seats free on paid plans | Mar 2025 raised Full-seat price and moved to admin-approved upgrades (https://www.figma.com/blog/billing-experience-update-2025/, https://www.figma.com/pricing) |
| Webflow Workspace | Per seat, 3 types | Full / Limited / Free seat | Editor access to the workspace | Dec 2024 decoupled seats from plan, removed seat caps; **guest access stays free for Freelancers and Agencies** (https://webflow.com/pricing) |
| Webflow Site plans | **Per published site** | Basic / CMS / Business / Premium | One hosted site | 2026 update added Premium tier and bandwidth add-ons; a Webflow bill mixes site plans + workspace + seats (https://webflow.com/pricing) |
| Slack | Per **active** seat | Per-seat, prorated | One active member | Fair-billing policy auto-credits members inactive 28+ days (https://slack.com/help/articles/218915077-Slacks-Fair-Billing-Policy) |
| Vercel | Hybrid: per seat + usage | Pro from $20/mo, includes $20 flexible credit | Seat + metered infrastructure | Apr 2024 unbundled bandwidth into granular metrics; Sept 2025 Pro moved to credit-based usage (https://vercel.com/blog/improved-infrastructure-pricing, https://vercel.com/blog/new-pro-pricing-plan) |
| Bitrise | Concurrency + seats (Enterprise) | Enterprise **minimum 10 seats** | A seat = one dev using Build Cache, 200 invocations/mo | Seat is a usage proxy, not an access licence (https://bitrise.io/pricing) |
| Codemagic | Concurrency, + pay-as-you-go OTA | **$1 per 2,500 installs**, no transfer/storage fees | Build concurrency; CodePush installs | Confirms the ~$1/2,500 install market rate arxa's overage marks up (https://codemagic.io/pricing) |
| Salesforce Agentforce | Reverted to **per seat** | Agentic Enterprise License Agreement | Agent access per user, with embedded usage caps | Moved off per-conversation pricing for predictability, Dec 2025 (https://www.theregister.com/software/2025/12/12/salesforce-opts-for-seat-based-ai-licensing/) |
| Cursor | Per seat + consumption limits | Per-seat with tiered usage | Editor seat, capped model usage | June 2025 change triggered apology and churn (https://www.saastr.com/cursor-our-users-love-per-seat-pricing-its-just-the-cost-side-makes-it-harder/) |
| Capawesome Cloud | **Flat, no seats** | Live Updates from $9/mo; full platform from $19/mo | Unlimited live updates, no per-seat fee | Appflow successor; closest flat-OTA comparable (https://capawesome.io/blog/alternative-to-appflow/) |
| **GoHighLevel** | **Per sub-account (client)** — users are unlimited | $97 Agency Starter (3 sub-accounts); $297 Agency Unlimited (unlimited sub-accounts) | One isolated client workspace | Unlimited contacts **and unlimited team members on every plan**; the price scales on clients, never on staff (https://www.gohighlevel.com/pricing) |
| Expo EAS | Per org, plan + usage | Free / Starter $19 / **Production $199** + usage | Build credit, concurrency, update MAUs (50K at Production) | No seat component at any tier (https://expo.dev/pricing) |
| Duda | Per site | Basic $25/mo monthly ($19 annual); Team $39/mo monthly ($29 annual) | A published site plus team access | Agency/white-label tiers exist above these; unit is the site (https://www.duda.co/pricing) |
| Adalo | Per app plan, flat | Starter $36/mo | App publishing + built-in database | Markets flat explicitly: "no usage-based charges… unlike platforms that meter by Workload Units or per-seat pricing" (https://www.adalo.com/pricing) |
| Bubble | Per app + workload units | From $69/mo + Workload Unit overage | App plus metered compute | **Secondhand** — figure read on Adalo's comparison page, Bubble's own page not read this session (https://www.adalo.com/pricing) |
| Shorebird | Platform fee + metered installs | Pro ~$20/mo incl. 50,000 patch installs; overage **$1 per 2,500** | OTA patch installs | **Repo-internal figure**, not verified primary — shorebird.dev/pricing was UNREADABLE on 2026-09-02 (cert error) |
| Bitrise | Flat + concurrency | Starter $99/mo (3 concurrency, ≤10 users); Pro $218/mo, unlimited members | Build concurrency | **Repo-internal figures**; seat minimum confirmed primary (https://bitrise.io/pricing) |
| Codemagic | Per-user PAYG or flat org | PAYG $10/user/mo + $0.095/min macOS; **Professional $299/mo unlimited users** | Concurrency and build minutes | Flat tier explicitly drops the per-user axis (https://codemagic.io/pricing/) |

## 4. Failure modes, with cases

**Per-seat: users route around the seat.** Webflow's own design concedes the
point — guest access is free for Freelancers and Agencies, and View seats are
free, because charging for every human who touches a file drives sharing of
credentials instead of buying seats (https://webflow.com/pricing). Figma reached
the same conclusion from the other side: it split one seat into Full/Dev/Collab/
View so that light users have a cheap legitimate option rather than an
illegitimate one (https://www.figma.com/blog/billing-experience-update-2025/).

**Per-seat: the vendor pays for idle seats in goodwill.** Slack's fair-billing
policy auto-credits any member inactive for 28+ days, a structural admission that
billing for logins customers do not use produces disputes
(https://slack.com/help/articles/218915077-Slacks-Fair-Billing-Policy).

**Per-seat: seat compression when the tool replaces the user.** This is the whole
2024–2026 thesis — if AI does the work, customers need fewer people and the seat
count falls even as value rises (https://www.growthunhinged.com/p/2025-state-of-b2b-monetization).
It bites products whose seats correlate with headcount doing the automated task.
It does not bite a business-admin module, where the seat correlates with a person
who has an HR record and a calendar.

**Flat unlimited: no expansion lever.** D102's own rejection note states it — a
flat per-company price gives no lever between a freelancer and a 50-person
agency. Poyar's data agrees that the loudest complaint from companies unhappy
with pricing is insufficient expansion revenue
(https://www.growthunhinged.com/p/the-state-of-b2b-monetization-in-2026).

**Usage-based: bill anxiety suppresses the usage you are trying to sell.**
Metronome's field research is blunt: buyers avoided AI features *even when free
credits were included*, because they feared unpredictable exposure; adoption is
driven by predictability, not price point
(https://metronome.com/blog/the-state-of-ai-monetization-field-research).
Cursor's June 2025 shift from unlimited to metered usage produced a public
apology (https://www.saastr.com/cursor-our-users-love-per-seat-pricing-its-just-the-cost-side-makes-it-harder/).
Salesforce reversed to seats for the same reason
(https://www.theregister.com/software/2025/12/12/salesforce-opts-for-seat-based-ai-licensing/).
The mitigation is arxa's existing one: overage off by default with a spend cap.

**Hybrid: the bill becomes unreadable.** Webflow's 2026 update produced a bill
combining site plan, workspace plan, seats, bandwidth add-ons, Analyze, Optimize
and Localization — enough moving parts that the vendor ships a calculator and
customers cannot tell which line changed (https://webflow.com/pricing).
The lesson for arxa: at most two meters per SKU, never three.

## 5. Three strategies for arxa

### Strategy A — Two SKUs, two axes (recommended)

- **Unit.** Pro: per developer seat. Scale: per org flat + per released app +
  OTA install overage. Agency: per member seat, bought by the org owner.
- **Price shape.** Pro $20–40/seat. Scale $149/org + $49/app over 3 + $1.50 per
  2,500 installs over 50k. Agency $X/seat (band not set — see open questions).
- **Optimises** for unit-follows-value. Every meter is a real cost driver or a
  real headcount of beneficiaries; none is a proxy.
- **Under-charges** the 3-person agency shipping 40 apps — they pay $149 plus
  app fees but consume a lot of support. **Over-charges** nobody badly; the large
  agency pays more only where it has more people in the business module.
- **Ladder.** Free → Pro (per-seat) → Scale (per-org) is a deliberate axis change
  at the Scale step, which is a selling point, not a bug: "your team stops being
  a line item." Agency sits *beside* the ladder, not on it, and can be bought by
  a Pro customer or a Scale customer alike.
- **Paddle shape.** Pro and Agency: subscription with `quantity = seats`
  (https://developer.paddle.com/api-reference/subscriptions/overview). Scale:
  subscription quantity 1, plus a recurring per-app price whose quantity is the
  app count. Install overage: **Paddle has no usage-records API** — meter
  externally (OpenMeter/m3ter) and add a custom line item to the upcoming
  transaction, or bill immediately via `POST /subscriptions/{id}/charge`
  (https://developer.paddle.com/get-started/how-paddle-works/ai-companies/,
  https://developer.paddle.com/api-reference/subscriptions/create-one-time-charge).
- **Recommendation: adopt this.** It is the only option where no decision has to
  be reversed and no meter is dishonest.

### Strategy B — Agency folded into Scale as one per-org flat tier

- **Unit.** One paid business tier, per org, unlimited seats, priced on apps and
  installs only. Agency sections unlock with the Scale entitlement.
- **Price shape.** Scale $149/org unchanged; agency sections included free.
- **Optimises** for the simplest possible pricing page and the strongest
  anti-FlutterFlow story ("we never count your people").
- **Under-charges** badly at the top: a 40-person firm running 3 apps pays $149
  for what is, for 37 of those people, a business-management product with no app
  usage at all. **Over-charges** the solo developer who wants Scale's app
  headroom but has no use for HR and accounting sections.
- **Ladder.** Cleanest ladder of the three — Free → Pro → Scale, one axis change,
  no side SKU. But it collapses two products with unrelated buyers into one
  price, which is why the money is left on the table.
- **Paddle shape.** Simplest: one subscription, quantity 1, plus per-app quantity
  and the same external-metering overage as Strategy A.
- **Recommendation: reject.** It reverses D102 for a tidiness gain and removes
  the only expansion lever the business-ops product has.

### Strategy C — Per-org flat with seat bands (the FlutterFlow 2025 shape)

- **Unit.** Per org, but the flat price steps by team-size band (e.g. 1–3, 4–10,
  11–25 members), the structure FlutterFlow moved to in Aug 2025
  (https://docs.flutterflow.io/accounts-billing/plan-pricing/).
- **Price shape.** Agency at three or four flat prices selected by headcount;
  Scale untouched.
- **Optimises** for predictability (the buyer sees one number) while keeping an
  expansion lever. It is the hybrid the 2026 data calls the most popular model
  (https://www.growthunhinged.com/p/the-state-of-b2b-monetization-in-2026).
- **Under-charges** the org sitting at the top of a band; **over-charges** the
  org one member over a boundary, which produces exactly the "should we not
  invite them" conversation per-seat is criticised for — with a bigger cliff.
- **Ladder.** Fits beside the ladder like Strategy A, same as Agency-as-side-SKU.
- **Paddle shape.** Distinct price IDs per band, quantity 1; band changes are
  plan swaps with proration, which means self-serve upgrade/downgrade UI and
  webhook handling for every boundary crossing — more work than `quantity`.
- **Recommendation: hold as the fallback.** Adopt only if per-seat Agency shows
  real invite-suppression in the first two quarters; the band cliffs are worse
  than the per-seat friction they replace.

## 6. Open questions

1. **Agency price band is still unset.** D102 fixes the unit but no figure exists
   anywhere in the repo. The internal-ops comparables (Productive, Scoro, Harvest,
   Teamwork, Float) are the right anchor set and were not resolved in time for
   this document.
2. **Minimum seat count for Agency.** Bitrise uses a 10-seat Enterprise minimum
   (https://bitrise.io/pricing); most PSA tools use 5. Not decided for arxa.
3. **Whether Agency needs free viewer seats.** Webflow and Figma both concluded
   yes (free Reviewer / View seats). Unknown whether arxa's business sections
   have a light-user role worth a $0 seat.
4. **Shorebird's current published rates could not be verified.** shorebird.dev/pricing
   returned a certificate error on 2026-09-02 (UNREADABLE:
   https://shorebird.dev/pricing/). The $1/2,500 figure the $1.50 overage marks
   up is repo-internal, corroborated only by Codemagic's identical published rate
   (https://codemagic.io/pricing) — not by a primary Shorebird page read here.
5. **paddle.com/billing/usage-based-billing returned HTTP 404** (UNREADABLE).
   Metering guidance was taken from the developer docs instead. Paddle's
   Classic-vs-Billing table lists "per-seat and metered billing plans" as
   supported, but that is marketing copy over the custom-line-item mechanism
   above — there is no usage-records endpoint. Confirm before building overage.
6. **Whether a Pro seat and an Agency seat should be one seat or two.** If a
   developer needs both, charging twice is a likely churn complaint; no source
   settles this.
