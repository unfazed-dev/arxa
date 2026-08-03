# Monetization and entitlements

Governing source: `docs/plans/scaffold-shell-kit-picker-decisions.md` decisions 17–20, 29–33 ("grilling round 2"). Supporting research: `docs/research/paygate-hook-points.md`, `entitlement-enforcement-practices.md`, `paygate-packaging-precedents.md`, `scale-pricing-and-credits.md`, `distribution-protection-inventory.md`.

## Scope & non-goals

In scope: the Free/Pro/Scale tier boundary, the entitlement backend that replaces the current offline-only licence, and where each enforcement point lives across scaffold/build/deploy.

Non-goals for v1: managed Supabase provisioning (D31 — BYO-Supabase only), metered LLM credits and any Totem-hosted inference (D32 — v1 is BYO-LLM only, on every tier, forever), and any online-only enforcement — offline continuation is mandatory (research: entitlement-enforcement-practices.md "Open flags").

## Pricing structure

Three tiers (D19), confirmed:

- **Free, forever, written into licence text:** design + eject (htmx artifact) and BYO-LLM. Free tier is unlimited local design/build/export — no identity, no metering (D16: anonymous work is free by construction).
- **Pro (~$20–40/seat/mo):** unlocks the scaffold entitlement (D17/D18 gate) — local builds, web deploys. Web deploy margin is thin and explicitly **not metered**.
- **Scale ($149/mo per org — D30):** unlimited seats, 3 released apps, 50,000 bundled patch installs across the fleet; store releases; Shorebird OTA; fleet management; custom domains. Per-org pricing, never per-seat — deliberate anti-FlutterFlow positioning (research: competitors' loudest complaint is FlutterFlow's $150/seat).

Scale add-ons resolved since D19 was written: managed-kit resale is **out of v1** (D31); credits/metered inference is **deferred to next version** (D32, BYO-LLM keeps full parity forever per zero-markup principles — no expiring credits, no per-plan credit revaluation).

**Two conflicts between the decision log and the research it cites — flag before ship:**

1. **Per-app overage above 3 apps.** D30 says "+$9/app beyond 3." The research it cites for the SCALE band (`scale-pricing-and-credits.md`, Q1 recommendation) says "+$49/app/mo beyond 3 apps." A 5.4x gap. The $49 figure is the one load-bearing in the research's own margin logic (positioned under Codemagic's $299, over Bitrise's $99 floor); $9 looks like a transcription error but nothing in the decision log explains the divergence. **Confirm which figure ships before pricing pages go live.**
2. **Shorebird overage margin.** D33 settles on "$1/2,500 (first-party-verified rate)" with no markup — a flat passthrough. The research (`scale-pricing-and-credits.md` Q1) explicitly recommends a **1.5x markup ($1.50/2,500)** specifically because Shorebird's raw cost is $0.0004/install and the doc names negative-margin OTA resale as "the single biggest financial hazard identified." Shipping D33's flat rate means Scale's OTA line carries **zero margin** — the exact risk the research was written to avoid. Also per D33: current per-tier Shorebird console prices are aggregator-sourced, not confirmed — pre-ship gate regardless of which rate is chosen.

One resolved (not a live conflict, but undocumented as such in the log): D19 originally states Shorebird orgs are "per-customer or customer-owned — never pooled on Totem Labs' plan." D33 (later, confirmed) reverses this: "Totem owns the Shorebird org... 50k installs bundled in SCALE." D33 supersedes D19 on this point; the log doesn't mark D19's clause as superseded, so a reader scanning decisions in order hits a direct contradiction. Worth a one-line correction in the decision log itself.

## Enforcement architecture

**What exists today** (`paygate-hook-points.md` Q1): a complete offline licence system, not a greenfield. `appboxd/lib/licence.dart` — Ed25519-signed licence file, 5-state verdict (valid/expired/grace/invalid/none), 30-day grace period, annual + perpetual tiers. `gate_deploy.dart:9` — "the paywall sits at first deploy," fail-closed, licence assertion runs first (`:23-28`), never surfaced as a sarif finding (payment failures shouldn't teach distrust of red gates). Critical structural gap: the licence payload has **no machine/host binding** — one file copies freely to unlimited machines (`distribution-protection-inventory.md` Q5). Dev bypass `APPBOX_DEV_LICENCE=1` is a plaintext env check at `gate_deploy.dart:97` — a one-word bypass, currently shippable.

**What changes (D17, D18):** the boundary moves from deploy to scaffold — "the moat is the automated design→Flutter conversion," and giving that away for free was a mistake in the original placement. The degrade-don't-block contract in `watermark.dart:16-17` ("invalid/expired/none never block emission") is **explicitly superseded** for the scaffold boundary; D18 retires `watermark.dart` entirely — it belonged to the old degrade-based model.

**New backend (D18, architecture per `entitlement-enforcement-practices.md`):** Supabase Auth via loopback-redirect PKCE (desktop) or `appbox://auth-callback` deep-link (no Supabase device-code flow — documented gap), with a paste-a-code Edge Function path for headless/SSH. Postgres: `subscriptions` (Stripe mirror), `entitlements` (`user_id`, `feature`, `status`, `expires_at`), `machines` (`user_id`, `fingerprint_sha256`, `platform`, `activated_at`, `last_seen_at`, `deactivated_at`) — RLS read-own-rows, **service-role-only writes**, synced from Stripe Entitlements (vendor dunning ≈8 retries/2 weeks, kept separate from the client's own offline-grace clock). `POST /activate` Edge Function takes a hashed fingerprint, enforces the seat cap (3 seats/machines, self-service deactivation), returns an appbox-signed JWT (`sub`, `fpr`, `feat:["emit.scaffold"]`, `exp` ≈7 days, `nbf`), cached at `~/.appbox/entitlement.jwt`. `emit scaffold` verifies the cached token **locally** against a pinned public key — no network call on the hot path — with silent background refresh inside the token's last 48h (Keygen's license-file model, not a heartbeat). The Ed25519 licence file is demoted to a signed+TTL offline-continuation artifact so Supabase downtime never blocks a paying user. The `APPBOX_DEV_LICENCE` bypass is compiled out of release builds.

**Where each gate sits (fail-closed unless noted):**

| Gate point | File:line | Status |
|---|---|---|
| `scaffoldMain` emitter, before first file write | `appboxd/bin/appbox.dart:606-607` | **Primary hook** — sits in the execution path, not the gate path; cannot be skipped by invoking the emitter directly (`paygate-hook-points.md` ranking #2) |
| `scaffoldGate` gate dispatch | `appboxd/bin/appbox.dart:352-353` | Secondary layer only — bypassable by calling the emitter directly |
| Deploy gate (existing, kept) | `appboxd/lib/gate_deploy.dart:23-28` | Already shipped, fail-closed; weakened today by the env bypass (fixed by compiling it out) |
| Phase declaration | `appboxd/lib/phases.dart:17,58` | Declarative only — not an execution funnel, do not rely on it alone |
| Server-brokered deploy credentials | Does not exist | Highest tamper-resistance ceiling, out of scope for v1 (would require new infra beyond the Edge Function) |

Machine fingerprinting follows documented per-OS conventions (macOS `IOPlatformUUID`, Windows `MachineGuid`, Linux `/etc/machine-id`/DMI), SHA-256 hashed before transmission, never raw.

## Workstreams (ordered)

1. **Supabase project + schema.** `subscriptions`/`entitlements`/`machines` tables, RLS policies, service-role write path. Stripe Entitlements sync webhook.
2. **`appbox login`.** PKCE/deep-link flow, keychain-vault token storage (reuses the pattern from D14's OAuth-first account connections), headless paste-a-code path.
3. **`/activate` Edge Function.** Fingerprint hashing client-side, seat-cap enforcement, JWT issuance and signing key management (first appbox-owned trust surface — carries new uptime/rotation/incident obligations, per `entitlement-enforcement-practices.md`).
4. **Local verification + refresh.** Pinned public key embedded in the client; cache at `~/.appbox/entitlement.jwt`; silent refresh inside last 48h; offline continuation logic reusing/replacing `licence.dart`'s grace-period math.
5. **Move the gate.** Insert entitlement assertion into `scaffoldMain` (`appbox.dart:606-607`) as primary; keep `scaffoldGate` (`:352-353`) as a redundant second layer. Retire `watermark.dart` and its call sites.
6. **Compile out `APPBOX_DEV_LICENCE`** from release builds; keep it dev-only.
7. **Stripe Checkout + pricing page.** Three tiers per the resolved pricing structure above, pending the two conflicts being settled.
8. **Shorebird overage billing.** Pooled-org install metering against whichever rate (D33's $1/2,500 vs research's $1.50/2,500) is confirmed pre-ship.

## Risks

- **No machine binding on the legacy licence file** carries forward until workstream 4 lands; until then, one Pro licence still copies freely.
- **Offline-continuation trust surface.** The Edge Function is appbox's first owned server — its downtime, key compromise, or clock-skew handling directly gates revenue. Needs incident-response ownership before ship, not after.
- **Air-gapped users are unaddressed.** The entitlement architecture assumes periodic connectivity (silent refresh, 7-day JWT). A genuinely air-gapped buyer needs a manual license-file checkout path (Keygen's model) or must be explicitly declared out of scope — not currently decided.
- **Org-pooling / seat abuse.** 3 seats/machines with self-service deactivation is the only stated control; no strategy is chosen yet for `machineUniquenessStrategy`-equivalent abuse (e.g., rapid activate/deactivate cycling to exceed the seat cap). Keygen's `overageStrategy`/`requireFingerprintScope` patterns are documented in research but not adopted as decisions.
- **Dunning clock mismatch.** Stripe's ~8 retries/2 weeks is deliberately kept separate from the client offline-grace clock (D18) — the two clocks drifting out of sync (e.g., Stripe cancels before the local JWT expires, or vice versa) is an integration risk, not yet a tested path.
- **Margin risk on Scale OTA overage** if D33's flat $1/2,500 ships as-is (see pricing conflict #2 above) — this is the exact hazard the research was written to flag.
- **Q4 (anti-tamper) is under-sourced** per `entitlement-enforcement-practices.md` — grade C, inference only, should not be treated as settled practice.

## Open questions

- Which per-app overage rate ships: D30's $9 or research's $49?
- Which Shorebird overage rate ships: D33's flat $1/2,500 or research's 1.5x $1.50/2,500?
- Is air-gapped/offline-forever use explicitly out of scope, or does it need a manual license-file path?
- What abuse-detection strategy (if any) backs the 3-seat cap beyond self-service deactivation?
- Pre-ship gate (D33): confirm real per-tier Shorebird console prices — current figures are aggregator-sourced.
