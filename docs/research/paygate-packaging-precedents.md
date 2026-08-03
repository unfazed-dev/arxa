# Paygate packaging precedents — free design vs paid build/deploy

**Retrieved 2026-08-03.** All pricing fetched live from official pricing pages that day unless marked
otherwise. Prices change constantly — re-verify before any pricing decision.

**Scope note:** Q3 (enforcement) and Q4 (build-vendor tiering) are already largely covered by
[`monetization-and-licensing.md`](./monetization-and-licensing.md) and
[`competitors-and-pricing.md`](./competitors-and-pricing.md). This doc does not re-derive them; §3 and §4
are deltas + fresh 2026-08-03 numbers. §1, §2 and §5 are the new material.

---

## Summary (≤200 words)

The premise "free, unlimited, production-grade, portable web output" has **no clean precedent**. Every
design-to-production tool surveyed gates *something* at the portability boundary, and the gate is one of
five things: **export** (Webflow code export, FlutterFlow code/APK download), **identity** (custom domain —
Framer, Lovable, FlutterFlow, Bolt), **branding** (Bolt watermark, Webflow badge), **commercial use** (Vercel
Hobby is non-commercial by ToS), or **generation usage** (v0 7 msgs/day, Lovable 5 credits/day, Bolt 300K
tokens/day). Free tiers universally hand back a *vendor-subdomain-hosted, watermarked, usage-capped* artifact
— good enough to evaluate, not to ship.

FlutterFlow is the closest structural analogue and it is instructive in the opposite direction from what
the appbox brief assumes: web publishing *is* free, but **code download costs $39/mo** — and that gate is
its single most-cited criticism after the Aug 2025 repricing.

Two documented backlashes matter: Figma's Dev Mode (free Inspect removed, ~51k-view forum thread) and
FlutterFlow's Aug 2025 repricing (users reporting $70→$135 for identical features). Both were **regressions
of previously-free capability**. That is the failure mode to design against, not the free/paid line itself.

---

## Q1 — Packaging precedents: where the line is drawn

### Webflow — *design free, host paid, export paid separately*

Two orthogonal billing axes, which is the notable structural trick.

| Axis | Tier | Price (2026-08-03) | What it unlocks |
|---|---|---|---|
| **Site plans** (per project) | Starter | Free | `webflow.io` subdomain, **2 static pages**, limited CMS, 1 GB bandwidth, 50 form submissions, Webflow AI, MCP server |
| | Basic | $15/mo billed yearly | Custom domain, 300 static pages, 10 GB bandwidth, unlimited forms, password protection |
| | Premium | $25/mo billed yearly | CMS, code components, site search, 50 GB–2.5 TB bandwidth tiers |
| | Team | $2,500/mo, annual contract | Org controls |
| **Workspace plans** (per org) | Starter Workspace | Free | — no code export |
| | Freelancer | UNVERIFIED (price not captured in fetch) | Code export, 1 Shared Library |
| | Agency | $35/mo billed yearly | Code export, unlimited Shared Libraries, unlimited staging sites, 3 free client seats/site, site-level roles, publishing permissions |
| **Seats** | Full seat | $39/mo per seat, billed yearly | Design full sites / admin |

Verbatim from the Workspace comparison table: *"Code export — Export clean, semantic HTML and CSS files for
your dev team. Dynamic content (CMS items/pages) can't be exported."* Starter Workspace row = `—`.

Webflow Help Center confirms export needs a **paid Workspace plan** and that a Site plan alone does not
include it; also that after export you need no ongoing Webflow plan for the exported site to work.
Exact minimum Workspace tier/price is **UNVERIFIED** — a forum thread references a "Workspace Core ~$28"
plan whose naming does not match the current pricing page's Starter/Freelancer/Agency.
Source: <https://webflow.com/pricing>, <https://help.webflow.com/hc/en-us/articles/33961386739347-How-do-I-export-my-Webflow-site-code>

**Line drawn:** design free → *hosting* paid (per site) AND *portability* paid (per workspace). Two separate
paywalls on the same artifact.

### Figma — *design free, handoff paid, per-seat*

Seat-typed, not feature-tiered. Starter is free with unlimited drafts and 150 AI credits/day (≤500/mo).

| Plan | Full seat | Dev seat | Collab seat |
|---|---|---|---|
| Professional | $16/mo | $12/mo | $3/mo |
| Organization (annual) | $55/mo | $25/mo | $5/mo |
| Enterprise (annual) | $90/mo | $35/mo | $5/mo |

Source: <https://www.figma.com/pricing/>

**Line drawn:** the design canvas is free; the *handoff to engineering* (Dev Mode inspection + MCP server) is
a paid seat class. Nothing about publishing.

### Framer — *canvas free, hosting paid, credits metered*

| Plan | Price | Free tier contents |
|---|---|---|
| Free | $0 | Free Framer domain, 1 GB bandwidth, "Design pages", 500 trial credits |
| Basic | $10/mo | Custom domain (free .com on yearly), 2 CMS collections, 50 GB bandwidth, 30 site pages, 1,000 CMS items, 20 CDN locations |
| Pro | $30/mo | 10 CMS collections, 100 GB bandwidth, 150 pages (then $20/100, 700 max), staging, branching w/ previews, redirects, site search, password protect, 300+ CDN locations |
| Enterprise | Custom | Unlimited editors, SSO, SCIM, uptime guarantee |

Additional editors $20/mo; **viewers free**. Overages are explicit: $40/100 GB bandwidth (2 TB max),
$40 per 10 CMS collections (40 max), $20 per 10,000 CMS items (40,000 max).
Source: <https://www.framer.com/pricing/>

**Line drawn:** free design + free *vendor-subdomain* publish; custom domain and real bandwidth are paid.
No code export at all — pure lock-in.

### FlutterFlow — *closest analogue, and it gates export*

| Plan | Price | Gate |
|---|---|---|
| Free | $0 | Visual dev env, 1,000+ templates, build mobile/web/desktop, API & data integration, **Web Publishing**, up to 2 projects, 10 Lite credits, 5 AI requests *lifetime*, up to 2 API endpoints |
| Basic | $39/mo ($29.25 billed annually per third-party review) | **Code Download**, **APK Download**, custom-domain web publishing, unlimited projects, test on local devices, one-click App Store deployment, 100 Lite credits/mo, 50 AI req/mo |
| Growth | $80 1st seat/mo, $55 2nd | GitHub integration, real-time collab (2 users), 2 open branches, localization, Swagger/OpenAPI import, VS Code ext., 200 credits/seat |
| Business | $150 1st seat/mo, $85 seats 2–5 | Collab ≤5 users, 5 branches, 3 automated tests, Figma frame import, **CLI access**, 400 credits/seat |

Source: <https://www.flutterflow.io/pricing>

**Line drawn:** free tier can *publish web* but cannot *take the code anywhere*. Portability is the single
paid trigger. This is the exact inverse of the appbox premise.

### Builder.io — *seat-priced, Fusion vs Publish split*

Two product lines (Fusion = visual IDE, Publish = visual CMS). Free = $0/user/mo, up to 5 users, GitHub/
GitLab/Bitbucket connect, Figma plugin, VS Code extension, admin-only role. Pro adds pay-as-you-go usage,
Agent Credit rollovers, 30-day activity history, built-in MCP servers, standard support. **Pro/Team dollar
prices render client-side and were not captured — UNVERIFIED.**
Source: <https://www.builder.io/m/pricing>

### Lovable — *free publish to subdomain, paid custom domain, credit-metered*

| Plan | Price | Notes |
|---|---|---|
| Free | $0 | 5 daily credits (~30/mo cap), no rollover, no top-ups, **5 `lovable.app` subdomains**, no custom domain |
| Pro | $25/mo | ~100 monthly credits, custom domains, Cloud hosting grants |
| Business | $50/mo | Higher grants |

Credit costs are task-complexity-priced (verbatim from FAQ: "Make the button gray" = 0.50 credits;
"Add authentication with sign up and login" = 1.20). Monthly credits expire 2 months after issue; top-ups
last 12 months; daily grants don't roll over. Lovable's own FAQ confirms custom domains require a paid plan,
though **already-connected domains keep serving after downgrade**.
Sources: <https://lovable.dev/pricing> (plan dollar figures render client-side — the $25/$50 figures are from
third-party 2026 reviews, treat as **semi-verified**), <https://lovable.dev/faq/domains/troubleshooting/custom-domain-paid-plan>

### Bolt (StackBlitz) — *token-metered, hosting free, branding + domain gated*

| Plan | Price | Contents |
|---|---|---|
| Free | $0 | Public + private projects, **300K tokens/day, 1M tokens/mo**, **Bolt branding on websites**, 10 MB file upload, **website hosting**, up to 333K web requests, unlimited databases |
| Pro | $25/mo billed monthly (yearly saves up to 28%) | No daily token limit, from 10M tokens/mo, **no Bolt branding**, private site sharing, 100 MB uploads, 1M web requests, token rollover, **custom domain support**, SEO boosting, expanded DB capacity, choice of DB provider, AI image editing |
| Teams | $30/mo per member | Everything in Pro + centralised billing, team access management, admin controls & user provisioning, private NPM registries, design-system per-package prompts |
| Enterprise | Custom | SSO, audit logs, compliance, dedicated AM, 24/7 support, custom SLAs |

Tokens roll over one additional month on paid plans (since 2025-07-01) and require an active subscription to
access. Token usage is dominated by syncing the project filesystem to the model, so cost scales with project
size, not just message count.
Source: <https://bolt.new/pricing>

**Line drawn:** hosting is free; the gates are **generation volume**, **branding removal**, and **custom
domain** — the same identity-and-usage pair as Framer/Lovable, with no export gate.

### v0 (Vercel) — *deploy is free, generation is metered*

| Plan | Price | Contents |
|---|---|---|
| Free | $0 | $5 included monthly credits, **Deploy apps to Vercel**, Design Mode, GitHub sync, **7 messages/day** |
| Plus | $30/user/mo | All models, $30 credits/user/mo, $2 free daily credits on login |
| Business | $100/user/mo | Same credits + training opt-out by default |
| Enterprise | Custom | SAML SSO, RBAC, priority access, SLAs |

Token-metered underneath (v0 Mini $1/$5 per 1M in/out; v0 Max Fast $10/$50).
Source: <https://v0.app/pricing>

**Line drawn:** the *only* v0 free-tier gate is generation volume. Deploy and export are free. This is the
one precedent whose shape is closest to "output is yours, free" — but it works because Vercel monetizes
downstream hosting, and Vercel Hobby is **non-commercial by policy** (see §5).

---

## Q2 — Which line held commercially, and the documented failures

**Dominant pattern: yes, "free design → pay to publish/export" is the norm**, but with an important
correction to the brief's framing. The gate is almost never on *design*; it is on one of:

1. **Portability** — Webflow code export (paid Workspace), FlutterFlow code/APK download ($39/mo)
2. **Identity** — custom domain: Framer ($10), Lovable ($25), FlutterFlow ($39), Webflow Basic ($15)
3. **Commercial rights** — Vercel Hobby "personal, non-commercial use"
4. **Generation/usage volume** — v0 7 msg/day, Lovable 5 credits/day, Bolt 300K tokens/day, Framer credits
5. **Branding** — Bolt watermarks free sites; Webflow's "Made in Webflow" badge removal is a paid Site plan

**No surveyed product gives away unlimited, production-grade, portable output on its free tier.** Appbox's
premise is therefore *not* the dominant pattern — it is a deliberate deviation. That may still be right
(it's a strong wedge against exactly the grievance below), but it should be adopted knowingly, not on the
belief that Webflow does it.

### Documented backlashes — both are *regressions of previously-free capability*

**Figma Dev Mode (Jan 2024).** The free Inspect panel was removed when Dev Mode launched as a paid seat.
Forum reaction was severe — the main "Dev mode pricing" thread drew 131 replies and 51,000+ views; users
described it as a "gut punch" and "bait-and-switch," reported bills jumping 2–3 seats → 7 seats, and cited
disproportionate pain for non-USD customers (~5x effective cost in BRL). Figma's mitigation (a read-only
Properties tab) was widely called "a downgrade." Multiple users named Penpot as an exit.
Sources: <https://forum.figma.com/t/licensing-dev-mode-at-a-high-cost/61481>,
<https://uxdesign.cc/the-dark-side-of-figmas-dev-mode-3337008c0f26>,
<https://blog.logrocket.com/ux-design/understanding-figma-billing-new-payment-structure/>

**FlutterFlow repricing (effective 2025-08-18).** Community reports of a plan going "from $70 to $135 for
literally the same features"; a user with a $600 PRO annual plan given 30 days to downgrade-and-lose-features
or pay $1,620; Trustpilot report that the **debug panel became paid-only**. The recurring structural
criticism is that the headline "free" hides that exporting your own work costs ≥$39/mo.
Sources: <https://community.flutterflow.io/discussions/post/new-pricing-plan-ripoff-or-not-g0fpjgL1nRZG919>,
<https://community.flutterflow.io/discussions/post/what-do-you-think-about-new-pricing-plan-OOzHxh2aEJrSDME>

**Lesson for appbox:** the failure mode is *taking back*, not *charging*. Whatever is free at v1 must be
treated as permanently free — write it into the licence, not just the pricing page. A free tier that is
*narrow but never shrinks* survives; a generous one that later contracts produces Figma-grade damage.

---

## Q3 — Enforcement for local tools (delta only)

Full survey — ed25519/ECDSA-P256 offline licence signing, keygen.sh offline-licence patterns, JetBrains
periodic online validation, activation-server-retirement risk (Adobe CS3), iLok-style hardware, RNBO/Max
export licensing — is in [`monetization-and-licensing.md`](./monetization-and-licensing.md). Do not duplicate.

**The delta this doc adds — reframe the question.** A local binary cannot be made tamper-proof, and the
codebase is open. Client-side licence checks against an open Dart CLI are a speed bump, not a control. The
productive question is not *"how do we stop a patched binary?"* but **"what does the server necessarily
hold?"** — i.e. what capability is structurally impossible to fork because it is not on the user's machine
in the first place. For appbox those are:

| Capability | Where it must live | Forkable? |
|---|---|---|
| Local scaffold + web build (htmx output) | User's machine | Yes — accept this, make it free |
| Shorebird **patch signing key + patch CDN** | Shorebird's servers (resold) | No — structural |
| App Store / Play Store credentials & submission | Vendor + store APIs | No — structural |
| Vercel/Cloudflare deploy tokens, DNS, env-var management | Appbox-managed accounts | No — structural |
| Provisioning of the above accounts (MCP account provisioning) | Server | No — structural |
| Build artifact attestation / release history / rollback state | Server | No — structural |

This is the Expo EAS / Codemagic lesson: their paywall is not enforced, it is *architectural* — the build
happens in their cloud, so there is nothing to crack. Appbox's equivalent is that **deploy management is a
server-held relationship (keys, credentials, release state), not a local feature flag.** Design the paid
tier around what genuinely cannot run locally, and the licence check stops being the load-bearing part.

Corollary: a licence key + periodic online validation with a generous offline grace window is still worth
having, but it should protect *convenience* features, not the revenue-critical ones. Anything whose loss
would be fatal to revenue should require a server round-trip that produces something the user cannot
synthesise (a signed patch, a deploy, a store submission).

**Two mechanisms the brief named that the existing doc does not cover** (it covers JetBrains perpetual-fallback
licensing, ed25519/keygen.sh offline signing, node-locked vs floating, Tailscale-style key expiry, iLok, and
activation-server-retirement risk — but not these):

- **Account login + server-issued short-lived tokens (Copilot CLI / `gh auth` shape).** The CLI runs an OAuth
  device-code flow against the vendor, stores a refresh token, and exchanges it for a short-lived access token
  per session. Tamper resistance is *nil* — the client is trivially patchable — but that does not matter,
  because the token is only useful for calling server endpoints that do the paid work. Offline behaviour is
  the trade-off: the tool is dead without network, so this suits capabilities that are inherently online
  (deploy, patch publish, store submission) and is wrong for anything the user expects to work on a plane.
  For appbox this is the natural mechanism for the Ship tier — and it composes with §3's table, because the
  token gates access to credentials appbox holds, not to a local code path.
- **Feature-flagged binaries.** One binary ships with paid code paths present but disabled behind a flag the
  licence check sets. Cheapest to build and the *weakest* — for an open Dart codebase it is a single-constant
  patch, and shipping the paid code to unlicensed users hands forkers the implementation. Only defensible for
  low-value convenience gating; never for the revenue-critical surface. The alternative (omit paid code from
  the free build entirely) costs a second build pipeline and still loses to a fork if the capability is
  genuinely local — which is the argument for making it *not* local.

See also `web-research-drift.md` — several enforcement-vendor numbers in the older doc predate 2026-08-03
and should be re-checked before use.

---

## Q4 — How build/deploy vendors tier themselves (fresh 2026-08-03)

### Shorebird (directly relevant — appbox would resell this)

Metered on **patch installs** (a successful update applied on a device). All plans include unlimited apps
and releases; tiers differ on installs, support channel, roles, and enterprise features.

| Plan | Price | Monthly patch installs | Overage |
|---|---|---|---|
| Starter | Free | 5,000 | none (hard cap — `-` in table) |
| Pro | $20/mo ($240/yr) | 50,000 | $1 per 2,500 installs |
| Business | $400/mo ($4,800/yr) | 1,000,000 | $1 per 2,500 installs |
| Enterprise | Custom | Custom | Custom |

Feature ladder from the fetched comparison table: signed patches, patch rollbacks, usage notifications,
staging and analytics appear across plans; **SAML and audit logs are Enterprise-only**; roles go
Admin/Developer → +Viewer → +App Manager; support Community Discord → Email → Private Discord/Slack.
**Billing mechanics — verified directly from <https://docs.shorebird.dev/account/billing/>:**

- Billing runs on **Stripe**; invoices go to the Stripe account email, not the Shorebird login email.
- Verbatim definition: *"A 'patch install' is a successful update applied on a customer's device."* Installs
  are billed only on successful download **and** application. *"Users always skip to the latest patch. If you
  send two patches before a user updates, you're only billed for one patch install for that user."*
- Billing is tied to the **organization owner's account**, not to each organization — one account can own
  multiple orgs and all inherit the owner's plan. (Relevant if appbox provisions Shorebird orgs on behalf of
  customers: a single appbox-owned account would pool every customer's installs onto one plan.)
- Self-service tops out around **2.5 million patches/month**; above that, or for invoice billing, tax support,
  alternative payment methods or custom procurement, Enterprise is required.

Sources: <https://shorebird.dev/pricing/> (comparison table fetched directly — installs, overage, roles and
feature ladder are verified), <https://docs.shorebird.dev/account/billing/> (billing mechanics verified).
**The dollar figures ($20/mo Pro, $400/mo Business) remain semi-verified** — both the pricing page and the
billing docs render or omit prices, so those came via web-search relay of Shorebird's own
<https://shorebird.dev/blog/simplified-pricing>. Confirm in the Shorebird console before modelling margin.
Note also that the pricing table's Business tier (1M installs) and the docs' 2.5M self-service ceiling leave
an unexplained band — treat the top of the self-service range as unresolved.

**Implication for appbox margin:** Shorebird's free 5,000 installs/mo is a hard cap with no overage. Any
appbox tier that promises patching must either sit on top of a customer's own Shorebird account (pass-through)
or absorb $1/2,500-installs COGS. A resold-at-flat-rate model has unbounded downside above the included cap
unless appbox mirrors the same metered overage.

### Expo EAS

| Plan | Price | Free/included |
|---|---|---|
| Free | $0 | **15 Android + 15 iOS builds**, low-priority queue, 60 min CI/CD Workflows, store submission, updates to 1K MAU, 25 projects, Launch + Observe access |
| Starter | $19/mo + usage | $45 build credit, high-priority queue, large workers, 3K MAU updates, 50 projects |
| Production | $199/mo + usage | $225 build credit, 2 concurrencies, 50K MAU updates, 10 env-var environments, SSO, priority support, 100 projects |
| Enterprise | Custom | $1,000 build credit, 5 concurrencies, 1M+ MAU, workflow insights, SLAs, 300 projects |

Source: <https://expo.dev/pricing> (Expo also publishes <https://expo.dev/pricing.md> as plain text for LLMs)

Note the shape: **free tier ships real builds and real store submissions** — the meter is volume + queue
priority + MAU, not capability. That is a materially friendlier line than FlutterFlow's.

### Codemagic

Pure usage, no capability gating.

| Axis | Price |
|---|---|
| Mac mini M2 | $0.095/min |
| Mac mini M4 | $0.114/min |
| Linux X2 / Windows | $0.045/min |
| Additional concurrency (PAYG) | $49/concurrency |
| Fixed price (annual) | $3,990 (M2) / $5,400 (M4) / $9,000 (M4 Max), 3 concurrent builds |
| Additional concurrency (fixed) | $1,500 / $1,800 / $3,000 |
| Burstable concurrency | $50–$60 above baseline, $150–$180 below (95th-percentile billed) |
| Individuals | Free: **500 macOS M2 min/mo**, unlimited apps, max 1 parallel build, community support |
| Enterprise | from $12,000/yr |
| **CodePush** (React Native, direct Shorebird competitor) | PAYG $1 per 2,500 installs; fixed from $99/mo ($990/yr) per 100K MAU |

Source: <https://codemagic.io/pricing/>

Codemagic's CodePush pricing is **identical to Shorebird's overage rate** ($1/2,500 installs) — that is the
market clearing price for code-push delivery, and it caps what appbox can mark up.

### Vercel (deploy target)

Hobby $0 (1M edge requests, 100 GB fast data transfer, CI/CD, WAF, CDN, DDoS) — **"personal, non-commercial
use"**, usage-capped, cannot purchase additional usage. Pro $20/mo with $20 included credit, 10M edge
requests, 1 TB transfer, then $2/1M requests and $0.15/GB. Enterprise custom, 99.99% SLA.
Source: <https://vercel.com/pricing>

---

## Q5 — The web wrinkle: portability vs managed deploys

The brief names Webflow's export-vs-host split as the closest analogue. It is the right analogue **but it is
not free** — Webflow charges on both sides (paid Workspace to export, paid Site plan to host). The genuinely
free-portability precedents are different in kind:

| Product | Take output anywhere | Managed hosting |
|---|---|---|
| Webflow | Paid Workspace (export ZIP: HTML/CSS/JS/assets, no CMS) — then **no ongoing plan needed** | Paid Site plan per project ($15–$25) |
| FlutterFlow | Paid ($39 Basic: code + APK download) | Free on FlutterFlow subdomain; custom domain paid |
| Framer | Never (no export) | Free on Framer domain; custom domain $10 |
| Lovable | GitHub sync (free tier includes GitHub sync) | 5 free `lovable.app` subdomains; custom domain paid |
| v0 | Free (GitHub sync, free deploy) | Free to Vercel Hobby — **non-commercial only** |
| Expo EAS | Source is yours (OSS framework) | Builds/updates metered, free tier real but small |

**The separation mechanism that actually recurs is not export-vs-host — it is `who owns the domain and the
credentials`.** In every case the free artifact lives at a vendor subdomain the vendor controls, and money
changes hands the moment the user wants (a) their own domain, (b) their own store listing, or (c) commercial
traffic. The "managed" half is *credential custody*, not file delivery.

For appbox this maps cleanly and favourably: htmx output is static files the user can rsync anywhere — that
costs appbox nothing and is a genuine differentiator against Framer/FlutterFlow. What appbox sells is not
the bytes but **the deploy relationship**: provisioned Vercel/Cloudflare accounts, DNS + domain wiring, env
var and secret management, deploy history and rollback, preview environments, and — on mobile — Shorebird
patch signing and store submission. That is the same structural paywall as §3's table.

One caution: if appbox's free web output is *deployed by appbox* to an appbox-managed Cloudflare/Vercel
account, appbox eats the bandwidth and Vercel's non-commercial Hobby ToS applies. "Free unlimited production
web output" must therefore mean **free unlimited local build + free export**, with any appbox-hosted preview
explicitly capped. Otherwise the free tier has unbounded COGS.

---

## Comparison table

| Product | Free forever | Payment trigger | Pricing unit | Portable output free? |
|---|---|---|---|---|
| Webflow | Design + 2 static pages on `webflow.io`, 1 GB bandwidth | Custom domain ($15 Site), code export (paid Workspace) | Per site + per workspace + per seat ($39 Full) | **No** |
| Figma | Unlimited drafts, 150 AI credits/day | Team files, Dev Mode inspect/MCP | Per seat, typed (Full/Dev/Collab) | n/a (no build) |
| Framer | Canvas + Framer subdomain, 1 GB bandwidth, 500 credits | Custom domain, bandwidth, CMS scale | Per site + credits + $20/editor | **No** (no export at all) |
| FlutterFlow | Visual builder, 2 projects, **free web publishing** | **Code/APK download**, custom domain, App Store deploy | Per seat ($39 → $150 1st seat) + credits | **No** ($39/mo) |
| Builder.io | Fusion free, ≤5 users, GitHub/Figma/VS Code integrations | Usage beyond free, MCP servers, roles, history | Per user/mo + agent credits | UNVERIFIED |
| Lovable | 5 credits/day (~30/mo), 5 `lovable.app` subdomains | Custom domain, credit volume | Credits + per plan (~$25/$50) | Partial (GitHub sync free) |
| Bolt | 300K tokens/day, 1M/mo, **free hosting**, 333K web requests, Bolt branding | Token volume, branding removal, custom domain | Tokens + $25/mo Pro, $30/member Teams | Yes (no export gate) |
| v0 | $5 credits/mo, 7 msgs/day, **free deploy to Vercel** | Generation volume only | Per user/mo + token metering | **Yes** (but non-commercial host) |
| Expo EAS | 15 iOS + 15 Android builds, 60 CI min, 1K MAU updates, store submission | Build volume, queue priority, MAU, concurrency | Subscription + usage credit | Yes (OSS framework) |
| Codemagic | 500 macOS M2 min/mo, unlimited apps, 1 parallel build | Build minutes, concurrency | Per minute / fixed annual | Yes |
| Shorebird | 5,000 patch installs/mo (hard cap) | Patch install volume | Per install ($1/2,500 over) | n/a |
| Vercel | Hobby: 1M edge req, 100 GB transfer | **Commercial use**, scale | Usage + $20/mo Pro | Yes |

---

## Three candidate tier structures for appbox

All three keep the brief's commitment — **local design + local web build + export are free forever** — and
differ in where the paid boundary sits. All three should carry a written "free-tier ratchet" promise (see
Q2 lesson): capabilities free at v1 stay free, additions may be tiered.

### Candidate A — "Deploy relationship" (recommended)

*Closest to the structural-paywall logic of §3, cleanest to enforce, least backlash-prone.*

| Tier | Price (indicative) | Contents |
|---|---|---|
| **Free** | $0 | Unlimited local design + scaffold; unlimited production htmx/web builds; full source export; unlimited local Flutter debug builds; manual deploy anywhere (user's own Vercel/Cloudflare/rsync) |
| **Ship** | ~$25/mo | Managed deploy shell: appbox-provisioned Vercel/Cloudflare, DNS + domain wiring, env/secret management, deploy history + rollback, preview environments; 1 seat; up to N apps |
| **Ship+Mobile** | ~$60/mo | Above + store submission automation + Shorebird patching passed through at cost + release/patch dashboards |
| **Team** | ~$40/seat/mo | Above + shared projects, roles, audit trail, SSO |

**Rationale.** The paid boundary is exactly the set of things that cannot exist on the user's machine
(credentials, signing keys, release state). No local licence check is load-bearing, so an OSS fork of the
CLI does not leak revenue — a forked CLI still has no deploy credentials. It also matches the strongest
observed pattern in §5 (money changes hands at credential custody). Risk: the free tier is *very* generous
for pure-web users, so web-only customers may never convert. Mitigate by making the managed-deploy DX
sharply better than manual, not by crippling the free path.

### Candidate B — "Free web, metered mobile" (FlutterFlow-inverted)

| Tier | Price | Contents |
|---|---|---|
| **Free** | $0 | Everything web, including managed web deploy to appbox-provisioned hosting, capped at N sites / X GB bandwidth/mo |
| **Mobile** | ~$39/mo | Flutter builds, store submission, Shorebird patching to 25k installs/mo, then $1/2,500 |
| **Business** | ~$150/mo | Higher install/bandwidth caps, concurrency, team seats, SSO, audit logs |

**Rationale.** Treats web as pure acquisition and mobile as the monetisable surface — defensible because
mobile has real COGS (store credentials, patch CDN, build machines) that web largely does not. Mirrors
Expo/Shorebird's volume-metered shape, which is the least-resented model surveyed. Risk: appbox eats web
hosting COGS on the free tier with no natural cap, and Vercel Hobby's non-commercial clause means appbox
must use its own paid infrastructure for customer sites. Only viable with hard, visible bandwidth caps.

### Candidate C — "Seat + usage hybrid" (Figma/Expo blend)

| Tier | Price | Contents |
|---|---|---|
| **Free** | $0 | Unlimited local design + build + export; 1 managed deploy target; 5 deploys/day |
| **Pro** | ~$20/user/mo + usage | Unlimited deploys, included usage credit (~$20) covering build minutes + patch installs, then metered at Shorebird/Codemagic market rate ($1/2,500 installs) |
| **Business** | ~$50/user/mo + usage | Roles, branches/environments, audit logs, SSO, priority queue, higher included credit |

**Rationale.** Included-credit-plus-overage is the shape both Expo ($45/$225 build credit) and Vercel ($20
credit) converged on, and it makes appbox's Shorebird COGS strictly pass-through rather than a margin risk —
the single biggest financial hazard identified in §4. Predictable unit economics. Risk: usage-based billing
is the hardest to communicate and the most common source of "surprise bill" churn; needs spend caps and
alerts from day one (Vercel and Framer both ship these, which is a tell).

**Recommendation:** Candidate A for launch simplicity and enforcement robustness, with Candidate C's
metered-overage mechanics grafted onto the mobile/patching line so Shorebird resale never runs at negative
margin. Candidate B is the weakest — it inverts the free/paid line onto the surface with the *least* COGS
justification and carries unbounded hosting cost.

---

## Uncertainty register

| Item | Status |
|---|---|
| Webflow Freelancer Workspace price; exact minimum tier for code export | **UNVERIFIED** — pricing page vs help-centre/forum naming conflict |
| Builder.io Pro/Team dollar prices | **UNVERIFIED** — rendered client-side, not in fetched HTML |
| Lovable Pro $25 / Business $50 | **Semi-verified** — plan cards render client-side; figures from 2026 third-party reviews. Credit mechanics and free-tier subdomain count are from Lovable's own FAQ (verified) |
| Shorebird Pro $20/mo, Business $400/mo | **Semi-verified** — comparison table (installs/overage/roles) and billing mechanics verified from official page + docs; dollar figures relayed from Shorebird's own blog via search. **Confirm in console before margin modelling** |
| Shorebird self-service ceiling: table says Business = 1M installs, docs say Enterprise needed above 2.5M | **Unresolved** — unexplained band between the two figures |
| Bolt | **Verified** from <https://bolt.new/pricing> 2026-08-03 |
| FlutterFlow Basic annual price ($29.25) | **Semi-verified** — third-party review; monthly $39 is verified from official page |
| All other figures | Verified from official pricing pages, fetched 2026-08-03 |
