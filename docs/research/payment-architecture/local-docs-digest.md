# Local docs digest — payment/entitlement gating & engine distribution

Cited digest of EXISTING decisions and code across ARXA, STUDIO, CAIRN for the architect redesigning payment/entitlement gating and engine distribution. Every fact below carries a `path:line` citation. Repos: ARXA=`/Volumes/business_ssd/arxa_digital_solutions/arxa`, STUDIO=`/Volumes/business_ssd/arxa_digital_solutions/arxa-studio`, CAIRN=`/Volumes/business_ssd/arxa_digital_solutions/cairn`.

## Q1 — Engine identity & distribution

The "engine" is two artifacts shipped together, never separately (D14, `arxa-studio/docs/plans/arxa-studio-grill-decisions.md:138`):

- **Compiled Dart CLI** (`arxa` binary) — gate dispatch lives in `arxa/bin/arxa.dart:428` (`case 'deploy': return deployGate(ctx);` etc.) and emitter dispatch at `arxa/bin/arxa.dart:686` (`case 'scaffold': exit(scaffoldMain(rest));` etc.). Note: actual hook lines are 90/118/428/686, not 352/606 as sometimes assumed — verify against current file before citing elsewhere.
- **dsh+PI harness runtime** — `arxa-studio/bin/arxa-studio.mjs:2-4`: "boots dsh with the arxa profile (identity, repo-law-only instructions, arxa gate). A composition, never a fork." The profile is materialized every launch from `profile/cordis.patch.yml` into `DSH_HOME/profiles/arxa` — a rewritten build product, not source of truth (`arxa-studio.mjs:13,29,63`).

**Distribution mechanism:** `arxa-studio/scripts/pack-sidecar.mjs` builds a bun-compiled, self-extracting Mach-O binary embedding a `tar.gz` payload (node_modules + plugins + node runtime) — `pack-sidecar.mjs:17,80-81,98`. First run extracts the payload to a tmp sibling then renames into place; extraction failure exits nonzero (`pack-sidecar.mjs:112,120-123`).

**Desktop packaging (D30):** "Tauri shell over the dsh engine... System webview, few-MB binary; the dsh + PI engine (`bin/arxa-studio.mjs`) runs as sidecar and stays the single core — CLI and desktop are the same engine (D14)... bundled sidecar — shell reads entitlement status via its JSON output, no Rust reimplementation of entitlement logic" — `arxa-studio-grill-decisions.md:256-259,269-270`.

CAIRN's own sidecar (`cairn-server`) uses the identical supervision pattern: "Probe-then-spawn (the engine sidecar's rider 1): an externally owned..." — `arxa/desktop/src-tauri/src/cairn_server.rs:76`.

## Q2 — Hosting decision (is the engine ever hosted remotely?)

**No hosted-engine decision is recorded anywhere searched.** A direct grep for "control of the engine" / "keeping control" across `arxa-harness-and-distribution.md` returns **no output** — do not quote that phrase as literal decision text.

What's actually decided (`arxa/docs/plans/arxa-harness-and-distribution.md`, Section C "Product line and payment gating", `:124-144`):
- Decision 7: "**The payment gate lives in the compiled engine at the emit boundary**" (`:137`) — control is achieved by embedding the gate in the shipped binary, not by hosting the engine on a server.
- Single executable, compiled engine (D21 AOT + embedded assets) — `:129`.

Section H "Deferred (not decided here)" (`:242-247`) lists only: buyer model access (BYO key vs metered gateway), Pi inside the product installer, and the full arxa→arxa rename pass — **hosting is not among the deferred items either**; it was never raised as an open question in this doc.

Consistent with D12 (STUDIO, below): "the check runs on customer hardware and is inherently crackable" (`arxa-studio-grill-decisions.md:126`) — an explicit acknowledgment that enforcement is local/client-side by design, not server-hosted. **Conclusion: engine hosting is a non-decision — the recorded architecture is local-compiled-binary-with-embedded-gate, full stop.**

## Q3 — Entitlement architecture

Current production mechanism is `arxa/lib/entitlement.dart` (docblock, top of file): Ed25519-signed JWT, `enum EntitlementStatus {valid, grace, expired, invalid, none}`. "**Never fails open**: unreadable/missing/invalid/expired/fingerprint-mismatch all map to a non-unlocking verdict." Grace: `exp < now <= exp + gracePeriod` unlocks (offline continuation, Supabase downtime never blocks a paying user). The docblock explicitly says this "mirrors licence.dart's 5-state shape" — its architectural predecessor, not a currently-live file (its own citations point only to `entitlement.dart`, no direct re-read of `licence.dart` this pass).

"kimitail" comment: expiry/nbf trust the local clock — a user who sets their clock back extends their own entitlement. "Accepted ceiling (same as licence.dart: embed grace, expect clock manipulation, accept it); the upgrade path is the silent refresh in the plan, not more local cleverness."

Token minting: PRODUCTION public key is embedded (Ed25519, hex constant); "the private half lives ONLY in the Supabase secret `ENTITLEMENT_ISSUER_JWK`... Tokens are minted exclusively by the `/activate` Edge Function (`docs/plans/entitlement-backend-runbook.md` §1, §7)" — entitlement.dart docblock.

**Backend (`arxa/deploy/supabase/functions/activate/index.ts:1-34`):** POST `/activate` mints the JWT; also serves `DELETE /machines/:fpr` (self-service seat deactivation). Auth = Supabase user JWT; all DB writes go through service role. `SEAT_CAP = 3` machines per user (`:21`), platforms `{macos, windows, linux}` (`:22`).

**Schema (`arxa/deploy/supabase/schema.sql`):** `subscriptions` table mirrors Stripe verbatim (`stripe_customer_id`, `stripe_subscription_id`, `status` — `:8-13`); `entitlements` (`:19`); `machines`, seat-capped, self-service deactivation (`:27-28`). RLS: users read own rows; **all writes service-role-only** — "the /activate Edge Function and the Stripe webhook, never the client" (`:3-5,43,54-55`).

**Fail-closed carried forward:** paygate-hook-points.md (research doc citing primary source) quotes `arxa/lib/gate_deploy.dart:9-11`: "the paywall sits at first deploy … failing CLOSED," licence assertion runs first (`:23-28`). This is the same fail-closed posture entitlement.dart states for itself.

**Refresh (not yet built):** `entitlement-backend-runbook.md:208-214` — "Already shipped locally: offline verification, machine binding, 30-day grace. Still to build (needs this backend): silent background refresh of the cached token inside its last 48h (Keygen's license-file model)... never destructive: a failed refresh leaves the cached token in place."

## Q4 — Stripe touchpoints (the central finding)

**Two unrelated Stripe surfaces exist. A Paddle/Lemon Squeezy switch affects only the first.**

**Surface 1 — arxa's own billing (Paddle-switch scope: YES).** Currently implemented as direct Stripe integration:
- `arxa/deploy/supabase/functions/stripe-webhook/index.ts:1-22` — "the ONLY writer" of `subscriptions`/`entitlements` tables; deployed with `--no-verify-jwt` (caller auth = Stripe's HMAC signature, not a Supabase session, `:3`); handles `customer.subscription.created/updated/deleted` + `checkout.session.completed`; `FEATURE = 'emit.scaffold'` (`:22`).
- `deploy/supabase/schema.sql:8-13` — `stripe_customer_id`, `stripe_subscription_id`, `status` columns; `deploy/supabase/seed.sql:71` — test fixture using those same columns.

**But this is superseded by a later, undecided-vs-decided-but-unbuilt state.** `arxa-studio/docs/plans/arxa-studio-grill-decisions.md` (958 lines, last commit 2026-09-01 — one day before this digest, and after the Stripe backend above was built):
- **D12 — "Payment gate provider: B, merchant of record"** (`:119-126`): "Paddle or Lemon Squeezy handles checkout, global sales tax/VAT, and issues license keys; ~5% fees accepted as the cost of not being the merchant... Enforcement goal is honest-user + server-side issuance, not DRM."
- **D15 — "One billing system for the whole family"** (`:146-161`): "The D12 merchant of record (Paddle/Lemon Squeezy) is the single money pipe for everything: one-time kit/tier purchases in arxa AND the Agency subscription. arxa.dev issues/holds entitlements only — it never touches money." References an existing freemium gate at `designs/arxa-studio/evidence/plans-paywall/` (`plans_viewmodel.js`, `attemptCheckout`/`applyUpgrade`) that "gets retrofitted onto MoR checkout."

**Net: Stripe is the currently-coded merchant; Paddle/Lemon Squeezy is the currently-decided (but not yet implemented) merchant.** The Supabase entitlement-issuance architecture (schema, `/activate`, JWT minting) is provider-agnostic in design — D15 states arxa.dev "never touches money," only issues entitlements — so a Paddle swap replaces the webhook handler and its Stripe-specific fields, not the entitlement JWT system itself.

**Surface 2 — `kit/payments/` (Paddle-switch scope: NO).** `arxa_kit_stripe_payments_provider.dart` is a client-app SDK: "Stripe PaymentSheet (card entry + Apple Pay / Google Pay + 3DS) over `flutter_stripe`. PaymentIntent creation stays server-side behind the `ArxaKitStripeBackend` port; the app sees only the client secret." Non-goals section: "server-side capture implementation (the kit defines the backend ports; **your server** implements them)" — this is a library arxa STUDIO's end users embed in the apps *they* scaffold and ship; "your server" is the end-user's own backend, unrelated to arxa's billing. A PayPal provider ships alongside it. This surface is untouched by any arxa-side Paddle decision.

## Q5 — Supabase's role

**Two separate Supabase trees exist in ARXA — a structural finding for the architect.** `arxa/supabase/migrations/` holds product-data migrations (dial/drawings tables) plus `20260826_billing_tier_agency.sql` — full text: "unify tier vocabulary across the one billing family (D15). 'pro'/'scale' remain arxa's tiers; 'agency' is arxa studio's paid tier (D8/D9)" — it alters the `subscriptions_tier_check` constraint to `('pro','scale','agency')`. Meanwhile `arxa/deploy/supabase/` holds the actual entitlement-backend infra: `schema.sql`, `seed.sql`, `functions/stripe-webhook/`, `functions/activate/`, `functions/_shared/entitlement_jwt.ts`, `scripts/keygen.mjs`, `secrets/entitlement-issuer.jwk.json`. **Both trees write to the same `subscriptions` table** — worth reconciling before any provider migration touches schema.

**Scope: Supabase is an "agency"-tier-only dependency, never a free-studio one.** D8 (`arxa-studio-grill-decisions.md`, "STUDIO grill D8 D9" extract): "arxa agency (paid tier): payment-gated upgrade that adds the business layer... **This is where Supabase lives** (the operator's client DB), not in studio. Evan's own use of Supabase is an *agency* concern, not a studio feature." D11 header: "Supabase SSOT split (agency tier): C, split by kind" (`:102`).

**Ownership boundary, enforced today at the code level:** `arxa-studio/CLAUDE.md:1-4` — "The Supabase database connected to this environment belongs to Arxa Digital Solutions... arxa studio is distributed software. Its users (including free users) do NOT get access to this database... never design an arxa studio feature that requires the Arxa Digital Solutions database to function... every feature that can use a database must have a local-only fallback."

**Confirmed: zero live Supabase wiring in STUDIO today.** `arxa-studio/plugins/account-mirror/lib/providers.js` header: "The provider seam (D45)... Two implementations ship: `createLocalProvider()` — the DEFAULT: offline, no arxa account, no network... `RemoteAccountProvider` — the shape of the future arxa backend provider: interface + typed errors only. **NO HTTP, NO Supabase, NO Arxa-DB dependency**; `fetchArtifacts()` always throws `ProviderNotImplementedError` in this build." Confirms the ownership boundary is currently a hard stub, not just policy.

## Q6 — Cairn's role

CAIRN is a general-purpose, from-scratch Rust local-first Postgres sync engine (Apache-2.0, alpha/Phase 3) positioned against PowerSync/ElectricSQL/Zero — architecture is Postgres/Supabase → `cairn-server` (replicator/predicate engine/fan-out router) → WebSocket → `cairn-core` (LWW+CRDT merge state machine) → per-platform bindings (FRB/UniFFI/wasm-bindgen/napi-rs) (`cairn/README.md:1-60`). ARXA consumes it two ways, both as sidecars supervised from `desktop/src-tauri/src/cairn_server.rs` (`:1,6,15,37-38,76,82,98,134` — "B2 sync-first, ADR-0042"): data sync, and push notifications via `cairn-pushd`, "one binary, SQLite registry, no Postgres needed... Credentials are operator-owned: APNs .p8 + team/bundle ids, FCM service-account JSON, stored in studio's local keystore — never in the repo, never in Supabase. Free users: push still works — `cairn-pushd` runs on the user's Mac beside the engine; no cloud required" (`cairn/docs/plans/cairn-integration-tauri-flutter-push.md`, Track B). CAIRN has its own independent auth model for managed multi-tenant deployments (ADR-0010, below) but carries **zero hard dependency on Supabase, Stripe, or Paddle** — it is orthogonal to the payment/entitlement system, not a component of it.

## Q7 — Security findings

- **CAIRN's `/sync` endpoint previously had no auth at all** — "an unbounded data-exfiltration hole" (paraphrased from Context; full Decision at `cairn/docs/adr/0010-sync-authentication-and-principal.md`). Fix: new `Principal{account_id,tenant_id}` domain type + `SyncAuth::authenticate(&token) -> Option<Principal>` port, resolved before WebSocket upgrade, `None` → HTTP 401. Two adapters: `AllowAnonymous` (default, `CAIRN_SYNC_AUTH=none`, single-tenant only, "logs a loud warning") and `SupabaseJwtAuth` (HS256-verifies a Supabase JWT). "A managed multi-tenant deploy MUST set `supabase-jwt`."
- **Explicit non-DRM threat model, stated twice.** `arxa-studio-grill-decisions.md:126`: "the check runs on customer hardware and is inherently crackable." `arxa/docs/research/entitlement-enforcement-practices.md` (industry research): anti-tamper inside a shipped binary is explicitly not a security boundary — matches the local decision, not contradicted by it.
- **Clock-trust ceiling, accepted knowingly.** entitlement.dart "kimitail" comment (above, Q3) — clock-back extends entitlement; accepted, upgrade path is server-side silent refresh, not more local cleverness.
- **RLS design:** `schema.sql` — users read-own-rows only; all writes service-role-only, bypassing RLS (`:3-5,43-48,54-55,94-96`). Any new provider's webhook (e.g., Paddle) needs the same `--no-verify-jwt` + provider-signature pattern currently used for Stripe (`stripe-webhook/index.ts:3`).
- **Unresolved fail-open/fail-closed tension, flagged but not resolved in current docs.** paygate-hook-points.md (historical/dated research, cites `watermark.dart:16-17`): "never block emission" (degrade to watermark) vs `gate_deploy.dart`'s fail-closed block-at-deploy. entitlement.dart's own docblock is fail-closed for its verdict, but doesn't itself resolve whether scaffold-time behavior degrades or blocks — worth an explicit current-state check before redesign, since the cited watermark.dart text may itself predate entitlement.dart.

## Q8 — Terms glossary

| Term | Meaning | Citation |
|---|---|---|
| engine | Compiled `arxa` Dart CLI + dsh/PI harness runtime, shipped together, "one core, two artifacts" (D14) | `arxa-studio-grill-decisions.md:138` |
| sidecar | Tauri-spawned child process (arxa-studio runtime, cairn-server, cairn-pushd) | `arxa/desktop/src-tauri/src/cairn_server.rs:1` |
| payload | The tar.gz bundle (node_modules+plugins+node runtime) embedded in the bun-compiled sidecar binary | `arxa-studio/scripts/pack-sidecar.mjs:17,80-81,98` |
| profile | `DSH_HOME/profiles/arxa`, rewritten every launch from `profile/cordis.patch.yml`; a build product, not SSOT | `arxa-studio/bin/arxa-studio.mjs:2-4,13,29,63` |
| cordis | A dsh preset ("Cordis preset") used to validate plugin surfaces in Creator mode; `cordis.patch.yml` is the profile-patch template | `arxa-studio-grill-decisions.md:800`; `arxa-studio.mjs:4,29,188,256` |
| entitlement | Server-issued Ed25519 JWT (fpr/sub/exp/nbf/features), 5-state verdict, cached at `~/.arxa/entitlement.jwt`, machine-fingerprint-bound | `arxa/lib/entitlement.dart` (docblock) |
| merchant of record (MoR) | D12's chosen model: a third party (decided: Paddle or Lemon Squeezy; implemented today: Stripe) handles checkout/tax/VAT and issues license keys so arxa is never the merchant | `arxa-studio-grill-decisions.md:119-126` |
| mount-point enforcer | The dsh-level check gating a folder/tree mount on entitlement status | `arxa-studio-grill-decisions.md:92` ("Pay gate = entitlement check at the mount point in dsh") |
