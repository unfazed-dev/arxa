# Pricing bands: Pro seat vs Agency seat

Anchors read from each product's current public pricing page, September 2026. Numbers are as shown on the page — no conversions or invented figures.

## Table A — Agency-seat anchors

| Product | Seat price (monthly / annual) | Min seats | Free viewer seats? | Source |
|---|---|---|---|---|
| Productive.io | $25/user/mo monthly; ~$24/user/mo annual (from "$240/mo for 10 users") | none stated (10 seats only required for wire-transfer payment) | not found on page | https://productive.io/pricing/ |
| Scoro | $17–$57/user/mo depending on app combo (USD); 13–17% off if annual | 5 users, explicit | not found on page | https://www.scoro.com/pricing/ |
| Harvest | Teams $11/seat/mo monthly, $9/seat/mo annual ($108/yr); Enterprise $17.50 monthly, $14 annual | none (Free plan = 1 seat) | not found (Free tier is a full seat, not a viewer role) | https://www.getharvest.com/pricing |
| Teamwork.com | Basics $9.99/user/mo annual; Accelerate $24.99/user/mo annual; monthly toggle exists, value not captured | none stated | not found on page | https://www.teamwork.com/pricing/ |
| Float | Starter $7/scheduled person/mo; Pro $12/scheduled person/mo | none stated (Enterprise is "100+ seat teams," not a floor) | yes — unscheduled people added as free guests | https://www.float.com/pricing |
| Bonsai | Basic $9 annual / $15 monthly; Essentials $19/$25; Premium $29/$39; Elite $49/$59 (all /user/mo) | none ("no minimums" per FAQ; discount at 30+ users) | not found on page | https://www.hellobonsai.com/pricing |
| Monday.com (Standard/Pro) | Standard $19 AUD/seat/mo annual; Pro $30 AUD/seat/mo annual — **page auto-localized to AUD, not USD** | none confirmed (seat slider defaults to 2-3, no enforced floor found) | yes — unlimited free viewers from Basic tier up | https://monday.com/pricing/ |
| ClickUp | Unlimited $7 annual / $10 monthly; Business $12 annual / $19 monthly (/user/mo) | none (Free plan allows unlimited free members) | partial — free GUEST allotments (5+2 per paid user on Unlimited, 10+5 on Business), not unlimited | https://clickup.com/pricing |
| Notion (Plus/Business) | Plus $10/member/mo; Business $20/member/mo (billing-cycle toggle not distinguishable in fetch) | none | not confirmed on page | https://www.notion.com/pricing |
| HubSpot Starter | UNREADABLE | — | — | https://www.hubspot.com/pricing/marketing |

## Table B — Pro-seat anchors

| Product | Seat price (monthly / annual) | Min seats | Free viewer seats? | Source |
|---|---|---|---|---|
| Cursor | Individual (Pro) $20/mo; Teams (Standard) $40/user/mo | none stated | not found on page | https://cursor.com/pricing |
| GitHub Copilot | Free $0; Pro $10/user/mo; Pro+ $39/user/mo; Max $100/user/mo | none | no (Free tier is the no-cost option, not a viewer role) | https://github.com/features/copilot/plans |
| JetBrains All Products Pack | Personal: $299 yr1 / $239 yr2 / $179 yr3+ (≈$25/$20/$15 per mo), or $29.90/mo pay-monthly. Commercial (org-bought): $979/yr (≈$81.58/mo), or $97.90/mo pay-monthly | none (per named user) | not found | https://www.jetbrains.com/all/ |
| FlutterFlow (Basic/Growth) | Basic $39/mo (1 user); Growth $80 1st seat + $55 2nd seat/mo; Business $150 1st seat + $85/seat for seats 2-5 | none (Basic is single-user by design) | not found | https://flutterflow.io/pricing |
| Retool | Team $10/builder/mo + $5/internal user/mo (annual view shown); Business $50/builder/mo + $15/internal user/mo | none (Free tier up to 5 users) | no — "internal user" is a cheaper paid tier, not free | https://retool.com/pricing |
| Linear | Free $0, unlimited members; Basic $10/user/mo billed yearly; Business $16/user/mo billed yearly | none | no (Free tier has unlimited members instead of a viewer role) | https://linear.app/pricing |
| Vercel Pro | $20/mo per Owner/Member seat | none | yes — Viewer Pro (read-only) seats free and unlimited | https://vercel.com/pricing |
| Supabase Pro (per org, not per seat) | From $25/mo per project/org (1st project included, +$10/mo per extra project); Team from $599/mo | n/a — priced per org/project, no seat unit | n/a | https://supabase.com/pricing |
| Figma (Dev/Full seats) | Professional: Full seat $16/mo; Dev seat $12/mo; Collab seat $3/mo | none | yes — free view-only "Inspect" access without Dev Mode | https://www.figma.com/pricing/ |
| Webflow Workspace seats | Freelancer $16/mo (1 seat incl.) billed yearly; Agency $35/mo (1 seat incl.) billed yearly; extra-seat price not shown on page | none (Starter tier is free, 1 seat) | yes — free client seats per site + free agency/freelancer guests | https://webflow.com/pricing |

## Bands

- **Agency-seat median** (flagship/mid tier, USD, n=8, excludes HubSpot and Monday's AUD figure): ~$19.50/seat/mo. IQR ~$14.50–$25/seat/mo.
- **Pro-seat median** (n=9, excludes Supabase which is org-priced): $16/seat/mo. IQR ~$13–$50/seat/mo — wide because JetBrains ($82/mo) and FlutterFlow Growth ($80/mo) sit far above the $10-20 IDE-assistant cluster.
- **Agency band to set**: $15–$25/seat/mo. It's a bolt-on admin module riding inside another app, not a standalone PSA suite like Scoro or Productive, so price mid-pack, not at the top.
- **Pro band to set**: $29–$39/mo, the upper half of the original $20–40 assumption. Generic code tools (Cursor, Copilot, Retool) cluster $10–20, but FlutterFlow — the one comparable that does the same job (design-to-app scaffold) — charges $39–80/seat, and that's the more relevant comp.
- **10-seat Agency minimum**: no support. None of the 9 readable Agency comps require 10 seats; Productive.io's "10 seats" is only a wire-transfer payment threshold.
- **5-seat Agency minimum**: weak support. Only Scoro (1 of 9) enforces a seat floor, and it's 5 users.
- **Free viewer seats**: not the default, but common. 6 of 19 readable comps offer some free viewer/guest capacity (Float, Monday, ClickUp in Table A; Vercel, Figma, Webflow in Table B). Worth matching — offer free client/stakeholder viewer seats.
- **One-seat-or-two evidence**: no comparable double-charges one person for two roles. Figma's Full seat already includes Dev Mode inspection (no separate Dev-seat charge on top); Retool's "builder" role subsumes "internal user" rather than stacking; Vercel's paid seat already includes viewer rights. Recommend: a developer who is also the org owner gets one seat (the higher tier), not a Pro charge plus an Agency charge.

## Unreadable pages

- **HubSpot Starter** — tried https://www.hubspot.com/pricing/marketing, https://www.hubspot.com/pricing, https://www.hubspot.com/pricing/starter-customer-platform (404), https://www.hubspot.com/pricing/all-products (404), https://www.hubspot.com/pricing/starter (404). The page is fully client-rendered — no pricing text is present in the server HTML, and a headless-browser retry failed because `agent-browser` isn't installed in this environment. No number invented for this row.
