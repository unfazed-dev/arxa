# MoR provider comparison — seller in Australia / Europe / Mauritius

Date: 2026-09-02. Written during the payment-architecture grilling session, in answer to
"research Lemon Squeezy as I will operate in Australia, Europe and Mauritius".
Supersedes the Paddle-vs-LS line in `docs/research/monetization-and-entitlements.md`
(that file predates the LS 2026 announcement).

Every claim below carries its source. Third-party numbers (fees quoted by competitors
or review sites) are marked *unverified*.

## 1. Seller eligibility by country

| Provider | Mauritius entity | Australian entity | EU entity | Source |
|---|---|---|---|---|
| Paddle | Yes — not on exclusion list (list is sanctions-only: Afghanistan, Belarus, Cuba, Iran, Iraq, Libya, Myanmar, N. Korea, Russia, Syria, Venezuela, Yemen, Zimbabwe, etc.) | Yes | Yes | https://www.paddle.com/help/start/intro-to-paddle/which-countries-are-supported-by-paddle |
| Lemon Squeezy | Yes — bank payouts listed for Mauritius | Yes | Yes | https://docs.lemonsqueezy.com/help/getting-started/supported-countries |
| Stripe Managed Payments | Not confirmed — locations page lists regions "North America, Europe, Asia Pacific" only; LS post says "35+ countries". Mauritius is very unlikely. | Likely (Stripe AU exists, docs render an Australia locale) — not confirmed | Likely | https://docs.stripe.com/payments/managed-payments/eligibility |
| Polar | Yes — Mauritius on Stripe Connect Express payout list | Yes | Yes | https://polar.sh/docs/merchant-of-record/supported-countries |
| Dodo Payments | Yes — eligibility is by the **director's government ID country**, not incorporation; Mauritius is on the list | Yes | Yes | https://docs.dodopayments.com/miscellaneous/accepted-countries-and-territories |

Dodo's rule is worth noting for any provider: KYC is done on directors/UBOs. A Mauritius
company with an Australian-passport director is fine everywhere above.

## 2. Payouts

**Paddle** — https://www.paddle.com/help/manage/get-paid/when-and-how-do-i-get-paid ,
https://www.paddle.com/help/manage/get-paid/can-i-be-paid-in-my-local-currency
- Monthly only: balance converts on the 1st, sent by the 15th, up to 3 working days more.
- Minimum payout threshold $100.
- Payout currencies: AUD, GBP, CAD, CNY, CZK, DKK, EUR, HUF, PLN, ZAR, SEK, CHF, USD. **No MUR.**
  A Mauritius bank account receives USD/EUR/AUD by wire; local-currency conversion is the bank's.
- Methods: bank/wire (local rails for AUD in AU, SEPA for EUR, UK for GBP), Payoneer, PayPal.
  Wire fee $15 for non-local-rail destinations; FX margin up to 1.5% if payout currency ≠ balance currency.
- Fee: 5% + $0.50 per transaction (https://www.paddle.com/pricing). Invoicing / purchase-order /
  bank-transfer B2B billing is on the "contact sales / custom pricing" tier, not self-serve.

**Lemon Squeezy** — bank payout to Mauritius and Australia; PayPal in 200+ countries.
Fee 5% + $0.50 (https://docs.lemonsqueezy.com/help/getting-started/fees).

**Polar** — payouts via Stripe Connect Express (so Stripe Payments need not exist in the seller's
country). Fee 4% + $0.40 per search results (*unverified*, https://polar.sh/docs/merchant-of-record/fees not fetched).

**Dodo** — fee 4% + $0.40 + 1.5% on international cards per third-party reviews (*unverified*).
Payouts twice-monthly per reviews (*unverified*).

## 3. The Lemon Squeezy situation (decisive)

Source: https://www.lemonsqueezy.com/blog/2026-update — JR Farr (CEO), 28 Jan 2026. Quotes:
- "I know it's been way too quiet on our end since our last real update."
- "That's what we're doing with Stripe Managed Payments: Stripe's merchant of record solution."
- "Today Managed Payments support merchants in 35+ countries and we're expanding to more later this year."
- "Very soon we will announce public access for Stripe Managed Payments allowing users to sign up without needing an invite."
- "Our goal is to provide Lemon Squeezy users an easy way to migrate to Stripe Managed Payments."
- Section heading: "Why Stripe Managed Payments is the future".

Reading: Lemon Squeezy is the on-ramp to Stripe Managed Payments, not a destination. Its own
CEO frames LS as the thing you migrate *from*. A new integration built on LS in Sept 2026 is
built on a product whose owner has publicly named its successor.

Stripe Managed Payments itself: MoR run by Stripe, direct integrations only (no Connect
platforms / Express accounts), digital products only, eligible tax codes include SaaS
(txcd_10103000/1/100…). Seller-location list not published as countries on the public page;
Mauritius not expected. This is the natural "move to Stripe later" path the user mentioned —
**if** the seller entity is in a supported location.

## 4. Recommendation

1. **Paddle** for D12 (MoR) unless the seller entity is Australian *and* Stripe Managed Payments
   confirms eligibility in writing — then Stripe MP is the better long-term home (same company
   the user already expects to move to; no second migration).
2. Drop Lemon Squeezy from the ADR options. Reason above.
3. Polar is the credible fallback if Paddle rejects the account or if self-serve B2B invoicing
   matters early (Paddle gates it behind sales). Polar has licence-key and benefit primitives,
   Stripe-Express payouts to Mauritius, open source — but it is a small company; treat as
   secondary.
4. Dodo: eligible, cheaper on paper, youngest company (2024). Not recommended as primary.

## 5. Open item that gates D12

Which legal entity signs the MoR contract — Mauritius, Australia, or EU company. This decides
whether Stripe Managed Payments is even on the table and which payout rails apply.
Not a research question; it is the user's decision.
