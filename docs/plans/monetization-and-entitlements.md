# Monetization and entitlements

Governing source: `docs/plans/scaffold-shell-kit-picker-decisions.md` decisions 17–20, 29–33 ("grilling round 2"). Supporting research: `docs/research/paygate-hook-points.md`, `entitlement-enforcement-practices.md`, `paygate-packaging-precedents.md`, `scale-pricing-and-credits.md`, `distribution-protection-inventory.md`.

## Scope & non-goals

In scope: the Free/Pro/Scale tier boundary, the entitlement backend that replaces the current offline-only licence, and where each enforcement point lives across scaffold/build/deploy.

Non-goals for v1: managed Supabase provisioning (D31 — BYO-Supabase only), metered LLM credits and any Totem-hosted inference (D32 — v1 is BYO-LLM only, on every tier, forever), and any online-only enforcement — offline continuation is mandatory (research: entitlement-enforcement-practices.md "Open flags").

## Pricing structure

Three tiers (D19), confirmed:

- **Free, forever, written into licence text:** design + eject (htmx artifact) and BYO-LLM. Free tier is unlimited local design/build/export — no identity, no metering (D16: anonymous work is free by construction).
- **Pro (~$20–40/seat/mo):** unlocks the scaffold entitlement (D17/D18 gate) — local builds, web deploys. Web deploy margin is thin and explicitly **not metered**.
- **Scale ($149/mo per org — D30):** unlimited seats, 3 released apps, +$49/app/mo beyond 3, 50,000 bundled patch installs across the fleet, overage at $1.50/2,500 installs (1.5x markup on Shorebird's raw rate); store releases; Shorebird OTA on a Totem-owned, pooled Shorebird org; fleet management; custom domains. Per-org pricing, never per-seat — deliberate anti-FlutterFlow positioning (research: competitors' loudest complaint is FlutterFlow's $150/seat).

Scale add-ons resolved since D19 was written: managed-kit resale is **out of v1** (D31); credits/metered inference is **deferred to next version** (D32, BYO-LLM keeps full parity forever per zero-markup principles — no expiring credits, no per-plan credit revaluation).

Both figures below were previously flagged as conflicts against the decision log's own cited research; both are now amended and resolved:

1. **Per-app overage above 3 apps: $49/app/mo** (D30, amended — the research figure from `scale-pricing-and-credits.md` Q1 is adopted; the earlier $9 was a transcription error, since corrected in the log).
2. **Shorebird overage rate: $1.50/2,500 installs**, a 1.5x markup on Shorebird's $1/2,500 raw rate (D33, amended — the research's margin-protecting recommendation is adopted; the flat zero-margin passthrough is rejected). Per-tier Shorebird console prices remain aggregator-sourced and still need first-party confirmation pre-ship.
3. **Shorebird org ownership: Totem-owned, pooled** (D33) stands. D19's earlier "never pooled on Totem Labs' plan" clause is struck and annotated SUPERSEDED-by-D33 in the log — no remaining contradiction between the two decisions.

## Enforcement architecture

**What exists today** (`paygate-hook-points.md` Q1): a complete offline licence system, not a greenfield. `arxa/lib/licence.dart` — Ed25519-signed licence file, 5-state verdict (valid/expired/grace/invalid/none), 30-day grace period, annual + perpetual tiers. `gate_deploy.dart:9` — "the paywall sits at first deploy," fail-closed, licence assertion runs first (`:23-28`), never surfaced as a sarif finding (payment failures shouldn't teach distrust of red gates). Critical structural gap: the licence payload has **no machine/host binding** — one file copies freely to unlimited machines (`distribution-protection-inventory.md` Q5). Dev bypass `ARXA_DEV_LICENCE=1` is a plaintext env check at `gate_deploy.dart:97` — a one-word bypass, currently shippable.

**What changes (D17, D18):** the boundary moves from deploy to scaffold — "the moat is the automated design→Flutter conversion," and giving that away for free was a mistake in the original placement. The degrade-don't-block contract in `watermark.dart:16-17` ("invalid/expired/none never block emission") is **explicitly superseded** for the scaffold boundary; D18 retires `watermark.dart` entirely — it belonged to the old degrade-based model.

**New backend (D18, architecture per `entitlement-enforcement-practices.md`):** Supabase Auth via loopback-redirect PKCE (desktop) or `arxa://auth-callback` deep-link (no Supabase device-code flow — documented gap), with a paste-a-code Edge Function path for headless/SSH. Postgres: `subscriptions` (Stripe mirror), `entitlements` (`user_id`, `feature`, `status`, `expires_at`), `machines` (`user_id`, `fingerprint_sha256`, `platform`, `activated_at`, `last_seen_at`, `deactivated_at`) — RLS read-own-rows, **service-role-only writes**, synced from Stripe Entitlements (vendor dunning ≈8 retries/2 weeks, kept separate from the client's own offline-grace clock). `POST /activate` Edge Function takes a hashed fingerprint, enforces the seat cap (3 seats/machines, self-service deactivation), returns an arxa-signed JWT (`sub`, `fpr`, `feat:["emit.scaffold"]`, `exp` ≈7 days, `nbf`), cached at `~/.arxa/entitlement.jwt`. `emit scaffold` verifies the cached token **locally** against a pinned public key — no network call on the hot path — with silent background refresh inside the token's last 48h (Keygen's license-file model, not a heartbeat). The Ed25519 licence file is demoted to a signed+TTL offline-continuation artifact so Supabase downtime never blocks a paying user. The `ARXA_DEV_LICENCE` bypass is compiled out of release builds.

**Where each gate sits (fail-closed unless noted):**

| Gate point | File:line | Status |
|---|---|---|
| `scaffoldMain` emitter, before first file write | `arxa/bin/arxa.dart:606-607` | **Primary hook** — sits in the execution path, not the gate path; cannot be skipped by invoking the emitter directly (`paygate-hook-points.md` ranking #2) |
| `scaffoldGate` gate dispatch | `arxa/bin/arxa.dart:352-353` | Secondary layer only — bypassable by calling the emitter directly |
| Deploy gate (existing, kept) | `arxa/lib/gate_deploy.dart:23-28` | Already shipped, fail-closed; weakened today by the env bypass (fixed by compiling it out) |
| Phase declaration | `arxa/lib/phases.dart:17,58` | Declarative only — not an execution funnel, do not rely on it alone |
| Server-brokered deploy credentials | Does not exist | Highest tamper-resistance ceiling, out of scope for v1 (would require new infra beyond the Edge Function) |

Machine fingerprinting follows documented per-OS conventions (macOS `IOPlatformUUID`, Windows `MachineGuid`, Linux `/etc/machine-id`/DMI), SHA-256 hashed before transmission, never raw.

## Workstreams (ordered)

1. **Supabase project + schema.** `subscriptions`/`entitlements`/`machines` tables, RLS policies, service-role write path. Stripe Entitlements sync webhook.
2. **`arxa login`.** PKCE/deep-link flow, keychain-vault token storage (reuses the pattern from D14's OAuth-first account connections), headless paste-a-code path.
3. **`/activate` Edge Function.** Fingerprint hashing client-side, seat-cap enforcement, JWT issuance and signing key management (first arxa-owned trust surface — carries new uptime/rotation/incident obligations, per `entitlement-enforcement-practices.md`).
4. **Local verification + refresh.** Pinned public key embedded in the client; cache at `~/.arxa/entitlement.jwt`; silent refresh inside last 48h; offline continuation logic reusing/replacing `licence.dart`'s grace-period math.
5. **Move the gate.** Insert entitlement assertion into `scaffoldMain` (`arxa.dart:606-607`) as primary; keep `scaffoldGate` (`:352-353`) as a redundant second layer. Retire `watermark.dart` and its call sites.
6. **Compile out `ARXA_DEV_LICENCE`** from release builds; keep it dev-only.
7. **Stripe Checkout + pricing page.** Three tiers per the resolved pricing structure above: Free / Pro / Scale at $149/mo + $49/app beyond 3.
8. **Shorebird overage billing.** Pooled-org (Totem-owned) install metering at $1.50/2,500 installs beyond the 50k bundle, including the 1.5x margin over Shorebird's raw $1/2,500 rate.

## Risks

- **No machine binding on the legacy licence file** carries forward until workstream 4 lands; until then, one Pro licence still copies freely.
- **Offline-continuation trust surface.** The Edge Function is arxa's first owned server — its downtime, key compromise, or clock-skew handling directly gates revenue. Needs incident-response ownership before ship, not after.
- **Air-gapped users are unaddressed.** The entitlement architecture assumes periodic connectivity (silent refresh, 7-day JWT). A genuinely air-gapped buyer needs a manual license-file checkout path (Keygen's model) or must be explicitly declared out of scope — not currently decided.
- **Org-pooling / seat abuse.** 3 seats/machines with self-service deactivation is the only stated control; no strategy is chosen yet for `machineUniquenessStrategy`-equivalent abuse (e.g., rapid activate/deactivate cycling to exceed the seat cap). Keygen's `overageStrategy`/`requireFingerprintScope` patterns are documented in research but not adopted as decisions.
- **Dunning clock mismatch.** Stripe's ~8 retries/2 weeks is deliberately kept separate from the client offline-grace clock (D18) — the two clocks drifting out of sync (e.g., Stripe cancels before the local JWT expires, or vice versa) is an integration risk, not yet a tested path.
- **Q4 (anti-tamper) is under-sourced** per `entitlement-enforcement-practices.md` — grade C, inference only, should not be treated as settled practice.

## Open questions

- Is air-gapped/offline-forever use explicitly out of scope, or does it need a manual license-file path?
- What abuse-detection strategy (if any) backs the 3-seat cap beyond self-service deactivation?
- Pre-ship gate (D33): confirm real per-tier Shorebird console prices — current figures are aggregator-sourced.
