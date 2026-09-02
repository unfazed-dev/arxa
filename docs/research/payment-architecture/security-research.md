# Payment, entitlement and engine-protection architecture — security research

Date: 2026-09-02. Docs-first: official documentation first, vendor changelogs/help second, blogs/community only as corroboration.
Method note: Paddle's docs host intermittently failed TLS from the research sandbox; pages marked **[search-only]** were confirmed via web-search excerpts of the official page but not fetched in full. Everything else was fetched and indexed.
Advisor consult was attempted twice and recorded as skipped (no sandbox auth, then rate-limited).

Context recap: `arxa` (proprietary Dart engine, must not ship) · `arxa studio` (Tauri shell + Node "dsh" plugin runtime, public, free tier) · `arxa studio agency` (paid npm-style package loaded by studio) · Supabase (auth, entitlements, edge functions) · today: Ed25519-signed entitlement JWT from an edge function, verified offline, machine-bound, cached on disk · goal: Paddle as merchant of record (MoR), possibly Stripe later.

---

## 1. Paddle Billing (API version 1)

### Merchant-of-record scope
- Paddle is the legal reseller/"seller of record": it collects, calculates and remits VAT/sales tax (100+ jurisdictions), issues compliant invoices (incl. EU B2B reverse-charge), and "takes on full liability for sales tax for all payments" (feature table). Fraud and "illegitimate chargeback protection" are listed as platform features. [paddle-classic-features], [paddle-help-vat]
- Chargebacks are raised against Paddle, which disputes them on your behalf; the fee ($15 card / $20 PayPal) is passed to the seller and refunded if Paddle wins. Adjustment types: `chargeback_warning`, `chargeback`, `chargeback_reverse`. **[search-only]** [paddle-help-chargebacks]
- Consequence: the customer's contract and invoice are with Paddle, not with you. This is what makes a later migration non-trivial (see below).

### API basics
- Base URLs: live `https://api.paddle.com`, sandbox `https://sandbox-api.paddle.com`; dashboards `vendors.paddle.com` / `sandbox-vendors.paddle.com`. Datasets, API keys, client-side tokens, webhook destinations/secrets are fully separate per environment. **[search-only]** [paddle-sandbox]
- Version pinning: header `Paddle-Version: 1` (current = version 1; sequential numbering; only breaking changes bump it; you cannot use a version older than your account default). Notification destinations carry their own API version, set when created. [paddle-versioning]
- Auth: `Authorization: Bearer pdl_live_apikey_…` server-side; browser/desktop use a *client-side token* with Paddle.js only. [paddle-versioning], [paddle-overlay-checkout]
- Sandbox test cards: `4242 4242 4242 4242` (success), `4000 0038 0000 0446` (3DS), `4000 0000 0000 0002` (declined). Sandbox retries failed webhooks 3× in 15 min; live retries 60× over 3 days; endpoint must answer 2xx within 5 s. **[search-only]** [paddle-sandbox]

### Product / price model
- Catalog = `product` → one or more `price` entities (`pri_…`), each with billing cycle, trial, currency overrides; checkout takes `items: [{priceId, quantity}]`. Subscriptions carry `items[].price.product_id`, which Paddle recommends mapping to features/entitlements. [paddle-overlay-checkout], [paddle-provision-access], [paddle-get-subscription]
- Subscription IDs `sub_[a-z\d]{26}`, customer IDs `ctm_…`. Statuses: `active`, `canceled`, `past_due`, `paused`, `trialing`. Response includes `scheduled_change`, `current_billing_period`, `items`, and optional `include=next_transaction,recurring_transaction_details`. [paddle-get-subscription]

### Checkout options
- **Overlay**: include `https://cdn.paddle.com/paddle/v2/paddle.js`, `Paddle.Initialize({ token: <client-side token> })`, `Paddle.Environment.set('sandbox')` for testing, `Paddle.Checkout.open({ items, customer })`. Prefilling `customer.email` + `customer.address.countryCode` skips the first page. [paddle-overlay-checkout]
- **Inline** (branded, embedded in your page): same Paddle.js with `settings.displayMode: 'inline'` and a frame target. [paddle-overlay-checkout] (link to inline tutorial), [paddle-inline-checkout **search-only**]
- **Hosted**: Paddle-hosted unique link per checkout; on live accounts "limited to approved mobile app companies", available on all sandbox accounts. Every automatically-collected transaction also gets a checkout link based on your **default payment link** (a page you host that includes Paddle.js; Paddle appends `_ptxn=<txn id>`); you cannot create transactions until a default payment link is set and (for live) domain-verified. **[search-only]** [paddle-default-payment-link], [paddle-hosted-params]
- Success handling: `settings.successUrl` on `Paddle.Checkout.open()` / `Paddle.Initialize()` or `data-success-url`; Paddle.js also emits `checkout.completed`. **[search-only]** [paddle-handle-success]

### Desktop-app constraints
- Paddle.js needs a real browser page on an approved domain. The documented pattern for non-web clients is Paddle's mobile-app guidance: link out to a Paddle checkout in the system browser, then return via deep link. **[search-only]** [paddle-linkout-hosted]
- Therefore for arxa studio: open a hosted page you control (default payment link with Paddle.js + overlay) in the system browser via Tauri opener; after `checkout.completed`/`successUrl`, redirect to a custom scheme (`arxa://…`) registered with the Tauri deep-link plugin (see §5). Do **not** try to render Paddle.js inside the Tauri WebView on a `tauri://` origin.
- Pass `customer.email` (from Supabase auth) and `customData` (e.g. Supabase user id) so the `subscription.created` webhook can be joined to the user without trusting the client.

### Webhooks — subscription lifecycle
- Sign-up: `customer.created`, `transaction.completed`, `subscription.created`. Lifecycle: `subscription.updated` is the documented catch-all for renewals, upgrades/downgrades, pauses, resumes, cancellations; `customer.updated`. Paddle explicitly says you do not need separate events beyond `subscription.created` + `subscription.updated` for access control. [paddle-webhooks-overview], [paddle-provision-access]
- Additional named events exist for granular handling: `subscription.activated`, `subscription.trialing`, `subscription.past_due`, `subscription.paused`, `subscription.resumed`, `subscription.canceled`, `subscription.imported`, `transaction.created`, `transaction.paid`, `transaction.payment_failed`, `transaction.past_due`. **[search-only]** [paddle-webhook-event-pages]
- Recommended integration shape: **lean cache** (store only access-critical fields, fetch the rest from the API on demand) vs **state mirror** (needs a reconciliation job). Access gating: `active` → full; `past_due` → warn; `paused`/`canceled` → revoke. [paddle-provision-access]

### Webhook signature verification
- Header `Paddle-Signature: ts=<unix ts>;h1=<hex>`. Compute HMAC-SHA256 over `"{ts}:{rawBody}"` with the destination's secret key (each notification destination has its own secret; secret is shown once in the dashboard). Compare to `h1` (constant-time). Official SDKs (`paddle.webhooks.unmarshal(rawBody, secretKey, signature)` in Node) enforce a **5-second timestamp tolerance** by default; manual implementations should do the same. Must use the raw body bytes. [paddle-webhook-sig]
- Compared to Stripe (`Stripe-Signature`, default 300 s tolerance in `constructEvent`), Paddle's default window is much tighter — clock skew on the receiver matters. [supabase-stripe-webhooks], [paddle-webhook-sig]

### Server-side reads and customer portal
- `GET /subscriptions/{subscription_id}` (permission `subscription.read`). List endpoints exist per entity with cursor pagination. [paddle-get-subscription], [paddle-classic-features]
- Customer portal: `POST /customers/{customer_id}/portal-sessions` (permission `customer_portal_session.write`), body `subscription_ids` (max 25). Returns `cpls_…` id and `urls.general.overview` + per-subscription deep links (e.g. `?action=cancel_subscription`). Links are temporary, must not be cached, and the portal must not be embedded in an iframe. [paddle-portal-session]

### Licence keys / seats
- Paddle Billing has **no licence-key issuance**: "Paddle-led fulfillment (product delivery, license key generation)" is listed as deprecated vs Classic. Seat counts are modelled as `quantity` on a subscription item; entitlement logic is yours. [paddle-classic-features], [paddle-provision-access]

### Migrating Paddle → Stripe later
- Paddle offers no "export my subscriptions to another PSP" API in the developer docs; Paddle's seller guide covers migrating *into* Paddle. Because Paddle is MoR, card data is Paddle's (as merchant) and moving it requires a PCI-compliant processor-to-processor transfer that Paddle must agree to; Stripe's side is the "Request a payment data import" (PAN import) process, importing as `pm_` or legacy `card_` objects, then re-creating subscriptions with Stripe Billing's import tooling. Expect: customer re-consent for some mandates (SEPA/ACH), new invoices from a new legal seller, and a period of running both. [stripe-pm-imports], [stripe-pan-import **search-only**], [stripe-import-subs **search-only**]
- Practical mitigation: keep your own `customers`/`subscriptions` tables keyed by *your* user id with a `provider` column, and gate entitlement on your table — never on a Paddle id in the client.

### Implications for arxa
- Treat Paddle as the source of truth for billing, and your Supabase `entitlements` table as the source of truth for access; join them on Supabase `user_id` carried in `customData`.
- Subscribe to `subscription.created` + `subscription.updated` (+ `transaction.completed` for one-offs); everything else is optional noise.
- Verify `Paddle-Signature` on the raw body with the per-destination secret and a 5 s window; run NTP-synced edge functions.
- Desktop checkout = system browser + your hosted Paddle.js page + `arxa://` deep-link return; never in the WebView.
- Seat/licence logic (machine limits, seat counts) lives in your edge function, not in Paddle.
- Design provider-agnostic tables from day one so a Stripe swap is a data migration plus a new webhook handler, not a client change.

### Sources
- [paddle-webhook-sig] https://developer.paddle.com/webhooks/signature-verification
- [paddle-webhooks-overview] https://developer.paddle.com/webhooks/overview
- [paddle-provision-access] https://developer.paddle.com/build/subscriptions/provision-access-webhooks
- [paddle-overlay-checkout] https://developer.paddle.com/build/checkout/build-overlay-checkout
- [paddle-inline-checkout] https://developer.paddle.com/build/checkout/build-branded-inline-checkout
- [paddle-get-subscription] https://developer.paddle.com/api-reference/subscriptions/get-subscription
- [paddle-portal-session] https://developer.paddle.com/api-reference/customer-portals/create-customer-portal-session
- [paddle-versioning] https://developer.paddle.com/api-reference/about/versioning
- [paddle-classic-features] https://developer.paddle.com/migrate/paddle-classic/features
- [paddle-sandbox] https://developer.paddle.com/sdks/sandbox/
- [paddle-default-payment-link] https://developer.paddle.com/build/transactions/default-payment-link/
- [paddle-hosted-params] https://developer.paddle.com/paddlejs/hosted-checkout-url-parameters
- [paddle-handle-success] https://developer.paddle.com/build/checkout/handle-success-post-checkout
- [paddle-linkout-hosted] https://developer.paddle.com/build/mobile-apps/link-out-mobile-app-hosted-checkout-app/
- [paddle-webhook-event-pages] https://developer.paddle.com/webhooks/subscriptions/subscription-activated/ , https://developer.paddle.com/webhooks/subscriptions/subscription-past-due/ , https://developer.paddle.com/webhooks/transactions/transaction-payment-failed/
- [paddle-help-vat] https://www.paddle.com/help/start/intro-to-paddle/how-paddle-is-able-to-take-on-your-vat-and-tax-responsibilities
- [paddle-help-chargebacks] https://www.paddle.com/help/manage/risk-prevention/understanding-chargebacks-with-paddle
- [stripe-pm-imports] https://docs.stripe.com/get-started/data-migrations/payment-method-imports
- [stripe-pan-import] https://docs.stripe.com/get-started/data-migrations/pan-import
- [stripe-import-subs] https://docs.stripe.com/billing/subscriptions/import-subscriptions

---

## 2. Offline desktop licence / entitlement security

### Signed tokens
- Ed25519 in JOSE is `alg: "EdDSA"` with an `OKP` key (`crv: "Ed25519"`); signatures are 64 bytes; no hash-agility or malleability pitfalls of ECDSA (RFC 8037, updated by RFC 9864). Use a maintained library (e.g. `jose`) and pin `alg` to `EdDSA` on verify — never accept `alg` from the token header. [rfc8037]
- Keygen's guidance (a licensing vendor, cited as practice not authority): the **public key and account id must be hard-coded into the application**, not read from a file or env, otherwise an attacker swaps keys without patching code. [keygen-cryptography]
- Keygen's offline model = signed (optionally encrypted) "license files" that embed expiry, grace period and entitlement data; the verifier checks signature, then `expiry`, and treats a stale file as expired (`ErrLicenseFileExpired` in the Go SDK). [keygen-offline], [keygen-cryptography]
- JetBrains' platform makes the threat model explicit: "There are no private keys in the platform (otherwise, they could easily be extracted/leaked)"; the IDE holds a *signed confirmation* from the server or a signed offline key, checked at startup and at least once a day. [jetbrains-license]

### Machine binding
- Bind the token to a stable machine fingerprint hashed server-side (`sub`, `machine_id` claim). Keygen's node-locked model: one licence ↔ one activated device; floating: N devices. Over-tight fingerprints (MAC, disk serial) cause false revocations after hardware/OS changes — prefer a per-install random key stored in the OS keychain plus a coarse fingerprint. [keygen-licensing-models]
- Stronger variant: per-machine key pair; server binds the entitlement to the public key (`cnf.jkt` thumbprint, as DPoP does) and the client proves possession on refresh. RFC 9449 defines the `DPoP` header, the `jkt` confirmation claim and server-supplied `nonce`s to block replay. [rfc9449]

### Revocation without a network, grace, clock tamper
- Offline revocation is impossible by definition; it is bounded by token lifetime. Standard pattern: short `exp` (days), a **refresh cadence** (attempt refresh every launch/24 h), and a **grace window** after `exp` (e.g. 7–14 days) before hard-locking. JetBrains' platform uses the same "check daily, tolerate offline" shape. [jetbrains-license], [keygen-offline]
- Clock tamper: store `last_seen_wall_clock` and a monotonic counter in the cache; refuse if wall clock moves backwards past the last-seen time; refuse tokens whose `iat` is in the future; use server time (`Date` header / response body) as the trusted reference whenever online. Keygen's SDK exposes `ErrSystemClockUnsynced` for the same purpose. **[search-only]** [keygen-go]
- Key rotation: publish a `kid` in the token and ship 2 public keys (current + next) in the client; rotate server-side, re-issue on next refresh; old key stays valid until the longest `exp`+grace elapses. Supabase's asymmetric signing-keys system is the model (zero-downtime rotation via JWKS discovery). [supabase-signing-keys]

### What tamper resistance is realistic in Node/Tauri
- Tauri's own security model: code in the Rust core or plugins "has full access to all available system resources"; only the WebView is constrained by capabilities. Nothing in the app is hidden from the local user. [tauri-security]
- Node SEA bundles the script into the binary but is not an obfuscation or encryption feature; the JS is recoverable from the blob. V8 bytecode tricks raise the bar slightly and break across Node versions. [node-sea]
- Therefore: signed entitlement checks stop *casual* sharing and *forged* tokens; they cannot stop a determined user who patches `verify()` to return true. Accept this.

### Recognised threat model
- Anything the client can compute, the attacker can compute. Protect on the server: the proprietary engine (§3), per-account quotas, seat counts, generated artefacts, and anything whose value is "the output" rather than "the button".
- Client-side checks should be cheap, honest UX gates; server-side checks are the security boundary.

### Implications for arxa
- Keep the Ed25519 JWT design; hard-code two public keys (`kid` current/next), pin `alg=EdDSA`, add `machine_id`, `iat`, `exp` (≤7 d), `grace_until`, `entitlements[]`, `seat_of` claims.
- Refresh on every launch and every 24 h; hard-lock only after `exp + grace`; log the reason locally.
- Add clock-tamper checks (last-seen wall clock + future-`iat` rejection) and treat server time as authoritative when online.
- Prefer per-install key pair bound to the token (DPoP-style) over hardware fingerprints; store it in the OS keychain.
- Do not spend effort on JS obfuscation beyond a minifier; spend it on moving value server-side.
- Revocation SLA = token lifetime + grace; document that to the owner.

### Sources
- [rfc8037] https://www.rfc-editor.org/rfc/rfc8037
- [rfc9449] https://www.rfc-editor.org/rfc/rfc9449
- [keygen-cryptography] https://keygen.sh/docs/api/cryptography/
- [keygen-offline] https://keygen.sh/docs/choosing-a-licensing-model/offline-licenses/
- [keygen-licensing-models] https://keygen.sh/docs/choosing-a-licensing-model/
- [keygen-go] https://github.com/keygen-sh/keygen-go
- [jetbrains-license] https://plugins.jetbrains.com/docs/marketplace/add-marketplace-license-verification-calls-to-the-plugin-code.html
- [supabase-signing-keys] https://supabase.com/docs/guides/auth/signing-keys
- [tauri-security] https://v2.tauri.app/security/
- [node-sea] https://nodejs.org/api/single-executable-applications.html

---

## 3. Keeping the proprietary engine under control

### Options
| Option | IP protection | Offline | Latency | Cost/ops |
|---|---|---|---|---|
| Hosted engine behind auth (API) | Strong — bytes never leave you | None | Network RTT + generation | You run compute; scales with usage |
| Obfuscated Dart AOT binary shipped | Weak — native binary is disassemblable; AOT snapshots hold structure/strings | Full | Local | Zero server cost |
| Tauri sidecar (`externalBin`) | Weak — same as above; sits in the app bundle | Full | Local | Zero server cost |
| Hybrid: free-tier features local, paid/heavy generation remote | Strong for the paid part | Partial | Mixed | Moderate |

- Sidecars are plain executables copied into the bundle (`src-tauri/binaries/<name>-<target-triple>`, e.g. `-aarch64-apple-darwin`) and launched via the shell plugin; the user can copy and run them. [tauri-sidecar]
- Node SEA / bundling does not hide code (§2). [node-sea]

### How comparable products do it
- **FlutterFlow**: the builder and generation run in FlutterFlow's cloud; the CLI/MCP "talks to FlutterFlow's cloud" and "doesn't execute your app"; users own the *exported* code (permissive-licensed helpers), not the generator. The generator is never shipped. [flutterflow-ownership], [flutterflow-cli **search-only**]
- **Figma plugins**: payment status (`figma.payments.status.type === "PAID"`) is asserted by Figma's platform, not by plugin code; checkout via `initiateCheckoutAsync`. [figma-payments]
- **JetBrains Marketplace**: licence state is a server-signed confirmation held by the platform; plugin code only *asks*. [jetbrains-license]
- Builder.io / Locofy / v0: no primary documentation found describing their generator location; they are web apps whose generation is server-side by construction. Not cited as evidence.

### Standard auth pattern: desktop client → hosted engine
- Login: OAuth 2.0 for native apps (RFC 8252 / BCP 212) — use the **external user-agent (system browser)**, PKCE, and a loopback (`http://127.0.0.1:<port>`) or private-use URI scheme redirect; embedded web views are discouraged. Supabase Auth supports this via its PKCE flow and the Tauri deep-link plugin as the redirect target. [rfc8252], [tauri-deep-link]
- Calls: short-lived Supabase access token (`Authorization: Bearer`) + the entitlement JWT (or server-side lookup) + optional DPoP proof bound to the per-machine key (`DPoP` header, `jkt`, server `nonce`). [rfc9449], [supabase-fn-auth-headers]
- Server: verify the user JWT locally against `SUPABASE_JWKS` (`https://<ref>.supabase.co/auth/v1/.well-known/jwks.json`), check `entitlements` via the service-role client, enforce **rate limits / quotas per user and per machine** in Postgres (e.g. a `usage` table with a daily counter), and return generated artefacts — never engine bytes. [supabase-fn-secrets], [supabase-jwts]
- Where to host: Supabase Edge Functions are Deno; the Dart engine needs a container/VM (Fly, Cloud Run, or a Cloudflare Worker fronting a container). Edge function = auth/quota gateway; engine = private service reachable only from that gateway.

### Implications for arxa
- Never ship the Dart engine as a sidecar or npm dependency; shipping it in any form is publication.
- Ship a thin local "engine client" in studio; run the scaffolder as an authenticated service. Free tier = quota-limited remote calls, not a local copy.
- Cache generated outputs locally so users can keep working offline on what they already generated.
- Gate every engine call on: valid Supabase JWT → entitlement row → per-machine + per-user rate limit → audit log.
- Use RFC 8252 login (system browser + PKCE + `arxa://` return) so the WebView never hosts credentials.

### Sources
- [tauri-sidecar] https://v2.tauri.app/develop/sidecar/
- [node-sea] https://nodejs.org/api/single-executable-applications.html
- [flutterflow-ownership] https://docs.flutterflow.io/miscellaneous/application-and-data-ownership
- [flutterflow-cli] https://docs.flutterflow.io/flutterflow-cli/build/
- [figma-payments] https://www.figma.com/plugin-docs/requiring-payment/
- [jetbrains-license] https://plugins.jetbrains.com/docs/marketplace/add-marketplace-license-verification-calls-to-the-plugin-code.html
- [rfc8252] https://www.rfc-editor.org/rfc/rfc8252
- [rfc9449] https://www.rfc-editor.org/rfc/rfc9449
- [supabase-fn-auth-headers] https://supabase.com/docs/guides/functions/auth-headers
- [supabase-jwts] https://supabase.com/docs/guides/auth/jwts
- [supabase-fn-secrets] https://supabase.com/docs/guides/functions/secrets

---

## 4. Supabase security

### RLS
- "Enable RLS on every table in an exposed schema." On existing projects a new `public` table starts with `select/insert/update/delete` granted to `anon`, `authenticated`, `service_role`; adding policies does **not** remove grants — revoke what signed-out/signed-in users should not have. `service_role` bypasses RLS and must stay server-side. Wrap `auth.uid()` as `(select auth.uid())` for performance; test with `supabase test db`. [supabase-rls]
- For arxa: `entitlements`, `machines`, `subscriptions`, `usage` → RLS `select` for the owning user only; **no** client `insert/update`; all writes via edge functions with the secret key.

### Keys
- Ship only the **publishable key** (`sb_publishable_…`) in studio; it "only reaches what RLS allows". **Secret keys** (`sb_secret_…`) bypass RLS and never leave your servers. Legacy `anon`/`service_role` JWT keys are being deprecated "by the end of 2026" — build on the new keys. [supabase-api-keys]
- Headers: `Authorization: Bearer <user JWT>` for users; `apikey: sb_…` for keys. Don't put API keys in `Authorization`. [supabase-fn-auth-headers]

### JWT verification in edge functions
- `verify_jwt` (default on) is a platform check on `Authorization` before your code runs; it accepts legacy HS256 and the new asymmetric signing keys. Turn it **off** for provider webhooks (no user JWT) and verify the provider signature yourself. [supabase-fn-auth-headers]
- `@supabase/server`'s `withSupabase({ auth: 'user' | 'secret' | 'publishable' | 'none' })` gives `ctx.supabase` (RLS-scoped), `ctx.supabaseAdmin` (bypasses RLS), `ctx.userClaims`. `auth: 'secret:<name>'` pins a named key. [supabase-fn-auth]
- Manual verification: `SUPABASE_JWKS` env (same as `/auth/v1/.well-known/jwks.json`), `kid` in header, `alg` `ES256|RS256` for signing keys; `iss` = `https://<ref>.supabase.co/auth/v1`. Prefer asymmetric signing keys — local verification, zero-downtime rotation. [supabase-fn-secrets], [supabase-jwts], [supabase-signing-keys]

### Secrets
- Edge Function secrets: `supabase secrets set` / `--env-file`, read with `Deno.env.get('PADDLE_WEBHOOK_SECRET')`; local `.env` at `supabase/functions/.env`. Defaults available: `SUPABASE_URL`, `SUPABASE_SECRET_KEYS`, `SUPABASE_PUBLISHABLE_KEYS`, `SUPABASE_JWKS`. [supabase-fn-secrets]
- **Vault** (`vault.create_secret()`, `vault.decrypted_secrets` view) is for secrets used *inside Postgres* (functions, triggers, `pg_net` webhooks). Put the Ed25519 **private signing key** and the Paddle webhook secret in Edge Function secrets (functions read them), and only mirror to Vault if a DB trigger needs them. [supabase-vault]

### Documented webhook pattern (Stripe example → Paddle)
- Official example: `verify_jwt = false`, `withSupabase({ auth: 'none' })`, read `req.text()` (raw body), `stripe.webhooks.constructEventAsync(body, sig, Deno.env.get('STRIPE_WEBHOOK_SIGNING_SECRET'), undefined, cryptoProvider)`, return 400 on failure. [supabase-stripe-webhooks]
- Paddle adaptation: header `Paddle-Signature`, `paddle.webhooks.unmarshal(rawBody, Deno.env.get('PADDLE_WEBHOOK_SECRET'), signature)` (Node SDK via `npm:`), 5 s tolerance, then upsert into `subscriptions`/`entitlements` with `ctx.supabaseAdmin`, idempotent on `event_id`, and respond 200 within 5 s (defer heavy work). [paddle-webhook-sig], [paddle-sandbox]

### Implications for arxa
- Publishable key + user JWT only in studio; secret key + Paddle API key + Ed25519 private key only in edge functions.
- Two functions: `paddle-webhook` (`verify_jwt=false`, signature-verified, idempotent) and `entitlement-issue` (`verify_jwt=true`, `auth:'user'`, checks `entitlements` + `machines`, signs the JWT).
- RLS: read-own-rows only; revoke `anon` grants on billing tables entirely.
- Migrate to `sb_publishable_/sb_secret_` keys and asymmetric signing keys now, before the 2026 legacy deprecation.
- Store `paddle_customer_id`, `paddle_subscription_id`, `provider='paddle'` alongside `user_id` so a Stripe swap is additive.

### Sources
- [supabase-rls] https://supabase.com/docs/guides/database/postgres/row-level-security
- [supabase-api-keys] https://supabase.com/docs/guides/api/api-keys
- [supabase-fn-auth] https://supabase.com/docs/guides/functions/auth
- [supabase-fn-auth-headers] https://supabase.com/docs/guides/functions/auth-headers
- [supabase-fn-secrets] https://supabase.com/docs/guides/functions/secrets
- [supabase-vault] https://supabase.com/docs/guides/database/vault
- [supabase-jwts] https://supabase.com/docs/guides/auth/jwts
- [supabase-signing-keys] https://supabase.com/docs/guides/auth/signing-keys
- [supabase-stripe-webhooks] https://supabase.com/docs/guides/functions/examples/stripe-webhooks

---

## 5. Tauri sidecar and desktop distribution security

### Sidecar / externalBin
- `bundle.externalBin: ["binaries/my-sidecar"]` in `tauri.conf.json`; a file per platform named `<name>-<target-triple>` (`rustc --print host-tuple`, Rust ≥1.84). Launched through the shell plugin (`Command.sidecar`) with an explicit capability permission; the binary is copied verbatim into the bundle (macOS: inside `.app/Contents/MacOS`). [tauri-sidecar]
- Why it is extractable: an app bundle is a directory; sidecars are ordinary executables the OS must be able to read and run, so the user can copy them. Code signing proves origin, not secrecy. [tauri-sidecar], [tauri-security]

### macOS signing + notarization
- Requires a paid Apple Developer account ($99/yr); free accounts cannot notarize. Certificate type `Developer ID Application` for outside-App-Store distribution; only the Account Holder can create it. [tauri-sign-macos]
- Tauri config: `bundle.macOS.signingIdentity`; CI env `APPLE_CERTIFICATE`, `APPLE_CERTIFICATE_PASSWORD`, `KEYCHAIN_PASSWORD`; notarization via `APPLE_ID` + `APPLE_PASSWORD` (app-specific) + `APPLE_TEAM_ID`, or `APPLE_API_KEY` + `APPLE_API_ISSUER` + `APPLE_API_KEY_PATH`; `--skip-stapling` flag exists. [tauri-sign-macos]
- Apple: notarization is required for Developer ID software on macOS 10.15+; hardened runtime is required; `xcrun notarytool submit … --wait`, then `xcrun stapler staple` the `.app`/`.dmg`/`.pkg` so Gatekeeper can validate offline. Apple's page is JS-rendered (fetch returned only the title); details corroborated via secondary sources. [apple-notarization], [notarization-secondary]

### Windows signing
- Needed to avoid SmartScreen warnings, not to run. **EV** certificates get immediate SmartScreen reputation; **OV** certificates accrue reputation over time (Tauri's OV guide only applies to certs issued before 2023-06-01 — newer certs require hardware/cloud HSM per CA/B Forum rules). Tauri supports Azure Key Vault and a custom `bundle.windows.signCommand`. Microsoft's managed option is Artifact Signing (formerly Trusted Signing) with FIPS 140-3 L3 HSMs. [tauri-sign-windows], [ms-trusted-signing]

### Updater keys
- Updater signatures "cannot be disabled". `tauri signer generate -w ~/.tauri/myapp.key` makes a minisign key pair; `pubkey` goes in `tauri.conf.json > plugins.updater`; private key via `TAURI_SIGNING_PRIVATE_KEY` (+ `_PASSWORD`) at build. Losing the private key = no more updates for installed apps; leaking it = attacker can ship updates. Endpoints must be HTTPS unless `dangerousInsecureTransportProtocol`. [tauri-updater]

### Deep link + opener (for checkout/login return)
- Deep-link plugin: `plugins.deep-link.desktop.schemes: ["arxa"]`; on macOS/iOS/Android schemes must be in config (no runtime registration); Windows/Linux can `register()` at runtime; handle via `onOpenUrl`. [tauri-deep-link]
- Opener plugin: `openUrl(url)`; restrict with capability `opener:allow-open-url` scoped to your domains. [tauri-opener]

### Implications for arxa
- A sidecar is fine for *non-secret* helpers (e.g. a Node runtime); it is not a hiding place for the engine.
- Budget: Apple Developer Program ($99/yr) + an EV/HSM-backed Windows cert or Microsoft Artifact Signing; both in CI with secrets, never on laptops.
- Generate the updater key once, store in a secrets manager with offline backup; treat it like the Ed25519 signing key.
- Register `arxa://` in `tauri.conf.json` (macOS needs config-time registration), and lock `opener` to `https://*.arxa.*` + Paddle domains.
- Sign and notarize every release before the updater can serve it; the updater signature is separate from OS code signing — you need both.

### Sources
- [tauri-sidecar] https://v2.tauri.app/develop/sidecar/
- [tauri-security] https://v2.tauri.app/security/
- [tauri-sign-macos] https://v2.tauri.app/distribute/sign/macos/
- [tauri-sign-windows] https://v2.tauri.app/distribute/sign/windows/
- [tauri-updater] https://v2.tauri.app/plugin/updater/
- [tauri-deep-link] https://v2.tauri.app/plugin/deep-linking/
- [tauri-opener] https://v2.tauri.app/plugin/opener/
- [apple-notarization] https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution
- [notarization-secondary] https://docs.bastion.tech/devices/apple/signing-notarizing , https://github.com/electron/notarize
- [ms-trusted-signing] https://learn.microsoft.com/en-us/azure/trusted-signing/overview

---

## 6. Paid code delivered as an npm package

### Why it is extractable
- An installed package is plain files in `node_modules`; npm itself warns that "even if your package is private, sensitive information can be exposed" once installed/distributed. Private packages require a paid npm user/org and only gate *download*, not *use*. [npm-private-packages]
- GitHub Packages npm registry: auth only via personal access token (classic) with `read:packages`; any token that can install can also be shared or leaked from a customer's `.npmrc`. [github-packages-npm]

### Options
1. **Private registry + per-customer token** (npm private scope, GitHub Packages, or a self-hosted registry). Real-world example: Font Awesome Pro — `@fortawesome:registry=https://npm.fontawesome.com/` and `//npm.fontawesome.com/:_authToken=${FONTAWESOME_PACKAGE_TOKEN}` in `.npmrc`; the token is per-account and revocable. Stops non-customers from downloading; does not stop redistribution. [fontawesome-private-npm]
2. **Encrypted bundle unlocked by entitlement** (studio downloads `agency.enc`, decrypts with a key delivered in the entitlement token). Weakness: the decryption key and the decrypted code both exist in the user's process memory and on disk; one `fs.writeFileSync` in a patched studio dumps it. It converts "can't download" into "must be a customer once".
3. **Server-side features**: the agency package is a thin client; the paid behaviour (engine calls, agency-only templates, exports) is executed or fetched per-request from the authenticated service. The only approach where the paid code is never on the customer's machine.

### What commercial plugin ecosystems actually do
- **JetBrains Marketplace**: plugin JARs are downloadable; enforcement is a platform-held, server-signed licence checked at startup and daily, plus recommended in-plugin `LicensingFacade` checks; JetBrains explicitly notes there are no private keys in the client. [jetbrains-license]
- **Figma**: plugin code is fully visible; `figma.payments.status` is computed by Figma's servers; trial logic uses `getUserFirstRanSecondsAgo()`. [figma-payments]
- **VS Code Marketplace**: no built-in paid extensions; vendors gate via their own accounts/servers. **[search-only]** [vscode-publishing]
- **Font Awesome Pro**: private npm registry + token (download gate only). [fontawesome-private-npm]
- Pattern across all of them: distribution is gated by tokens; **value** is gated by a server the vendor controls.

### Implications for arxa
- Distribute `arxa-studio-agency` from a private registry with per-customer, revocable tokens (download gate + audit trail), served by studio's plugin loader rather than `npm install` by the user.
- Assume the package is public the day it ships; put nothing in it you would not open-source (no engine code, no signing keys, no secrets).
- Make the package's paid features remote: agency templates/exports/engine runs are fetched or executed via the authenticated engine service with `agency` entitlement checks server-side.
- Skip the encrypted-bundle scheme unless you only need "customers-only download"; it adds complexity without a security gain over a private registry.
- Watermark generated artefacts and package builds per customer (embed `customer_id` in a build manifest) so leaks are attributable.

### Sources
- [npm-private-packages] https://docs.npmjs.com/creating-and-publishing-private-packages
- [github-packages-npm] https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-npm-registry
- [fontawesome-private-npm] https://docs.fontawesome.com/web/setup/packages
- [jetbrains-license] https://plugins.jetbrains.com/docs/marketplace/add-marketplace-license-verification-calls-to-the-plugin-code.html
- [figma-payments] https://www.figma.com/plugin-docs/requiring-payment/
- [vscode-publishing] https://code.visualstudio.com/api/working-with-extensions/publishing-extension

---

## Recommended security posture (ranked)

1. **Never ship the Dart engine.** Run it as a private service behind a Supabase edge-function gateway; studio (free and agency) talks to it over HTTPS with a user JWT + entitlement. This is the only control that actually protects the IP. (§3)
2. **Entitlements decided server-side, cached client-side.** Supabase `entitlements`/`machines`/`usage` tables are the truth; the Ed25519 JWT is a cache with `exp ≤ 7 d` + grace. Every engine call re-checks the table. (§2, §4)
3. **Paddle webhooks → Supabase, verified and idempotent.** `verify_jwt=false`, `Paddle-Signature` HMAC-SHA256 over `ts:rawBody`, 5 s window, upsert by `event_id`, 200 within 5 s. Listen to `subscription.created` + `subscription.updated` + `transaction.completed`. (§1, §4)
4. **Secrets placement.** Publishable key only in studio. Secret key, Paddle API key, Paddle webhook secret, Ed25519 private key: Edge Function secrets. Updater private key + Apple/Windows signing material: CI secrets with offline backup. (§4, §5)
5. **RLS everywhere on billing tables**, `anon` grants revoked, users can only `select` their own rows; all writes via `supabaseAdmin` in functions. Migrate to `sb_publishable_/sb_secret_` and asymmetric signing keys before the legacy deprecation. (§4)
6. **Desktop auth + checkout via system browser and `arxa://` deep link** (RFC 8252 + Tauri deep-link/opener with scoped capabilities). No credentials or Paddle.js inside the WebView. (§1, §3, §5)
7. **Per-machine key pair in the OS keychain, bound into the entitlement (`jkt`)**, plus per-user and per-machine rate limits on the engine gateway. Seat limits enforced in the edge function, not in Paddle. (§2, §3)
8. **Clock-tamper and rotation hygiene**: reject future `iat`, monotonic last-seen clock, two hard-coded public keys with `kid`, pinned `alg=EdDSA`. (§2)
9. **Sign and notarize every release** (Developer ID + notarytool + staple; EV/HSM or Microsoft Artifact Signing on Windows) and keep the Tauri updater signature mandatory. (§5)
10. **Agency package = thin client from a private registry with per-customer tokens**; assume it is public; paid behaviour lives on the server; watermark builds per customer. (§6)
11. **Provider-agnostic billing schema** (`provider`, `provider_customer_id`, `provider_subscription_id`) so Paddle→Stripe is a data migration + new webhook handler. (§1)
12. **Audit log** every entitlement issue/refresh/revoke and every engine call (user, machine, ip, quota) — this is what you will use to detect sharing, not client-side tricks. (§2, §3)

## Open questions for the owner

1. Is fully-offline use of the *scaffolder* a product requirement, or is "offline on already-generated projects" acceptable? (Decides §3 hosted vs hybrid.)
2. Expected engine call volume and acceptable latency/cost per generation — sizes the hosted engine and quota design.
3. Seat model for agency: per-user, per-machine, or floating N-of-M? What is the grace period after `exp` (7 vs 14 days)?
4. Will Paddle approve the account for hosted checkouts on live, or do we rely on a self-hosted default-payment-link page + overlay? Which domain hosts it?
5. Are we comfortable that customer invoices show Paddle as the seller (B2B VAT reclaim, procurement)? This is the main MoR trade-off.
6. Is a future move back to Stripe likely enough to negotiate PCI card-data export terms with Paddle up front?
7. Who holds the Apple Developer account (Account Holder must create the Developer ID cert) and the Windows signing identity/HSM?
8. Where do the Ed25519 private key and Tauri updater key get backed up offline, and who can rotate them?
9. Does the "dsh" Node plugin runtime need to load third-party plugins, or only arxa-published ones? (Determines whether the private-registry gate also needs code-signing of packages.)
10. Should free-tier engine use require an account (enables quotas/abuse control) or stay anonymous with a much smaller local feature set?
