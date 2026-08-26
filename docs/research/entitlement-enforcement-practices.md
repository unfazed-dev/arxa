# Entitlement enforcement practices for a locally-run paid engine

Reading-research, not measured findings. Claim grades: **A** official docs/vendor
statement, **B** corroborated secondary or documented-absence, **C** single source or
reasoned inference. **Checked 2026-08-03.**

**Scope / delta note.** This doc supersedes one recommendation in
[`monetization-and-licensing.md`](./monetization-and-licensing.md) §3 — "verified fully
offline … never phone home." That recommendation is retained for *expiry* but is
insufficient as a *gate*, for reasons in §4. Pricing, tier shape and the
charge-for-tool-not-output verdict from that doc and from
[`paygate-packaging-precedents.md`](./paygate-packaging-precedents.md) are unchanged and
not re-derived. Hook points and the current shipped implementation are in
[`paygate-hook-points.md`](./paygate-hook-points.md).

---

## Summary (≤150 words)

There is no single industry standard; there is a **standard composition**: a
server-issued, short-lived, machine-scoped credential, cached locally with an explicit
offline window, backed by a machine-activation table with a seat cap. Keygen documents
this most concretely (validate → activate fingerprint → optional heartbeat →
cryptographic license file for offline). JetBrains has moved the *opposite* way from
arxa's current design — its self-hosted floating License Server was discontinued
2026-01-01 in favour of cloud License Vault. Machine binding is universally
fingerprint-based (`IOPlatformUUID` / `MachineGuid` / `/etc/machine-id`), hashed, with
fuzzy matching and self-service deactivation. Anti-tamper inside a shipped binary is
explicitly *not* a security boundary — Flutter's own docs say obfuscation "does not
protect against reverse engineering." Supabase has **no first-party licensing guide**;
the pattern is composed from documented primitives. Stripe Entitlements +
`entitlements.active_entitlement_summary.updated` collapses most of the payment linkage.

---

## Q1 — Architecture: what actually gates a local engine

**Finding: the four options in the brief are not alternatives; the documented model is a
stack.** (Grade A for Keygen's model, B for the generalisation.)

Keygen — the only vendor that documents this end-to-end — defines the primitives as
License (entitlement), Machine (device/node), Policy (behaviour), User (identity), and
composes licensing models from them: perpetual, timed, node-locked, floating, feature,
metered, offline.
<https://keygen.sh/docs/choosing-a-licensing-model/>

The recommended client flow is identical for node-locked and floating, differing only in
`maxMachines`:

1. Validate the license key **with a fingerprint validation scope**
2. Activate the current machine if validation returns `NO_MACHINE` /
   `FINGERPRINT_SCOPE_MISMATCH` / `NO_MACHINES`
3. Optionally revalidate after activation

<https://keygen.sh/docs/choosing-a-licensing-model/node-locked-licenses/> ·
<https://keygen.sh/docs/choosing-a-licensing-model/floating-licenses/> ·
<https://keygen.sh/docs/activating-machines/>

Keygen recommends `strict` policies (a license with zero activations is invalid), which
is the load-bearing detail: **it makes "no server contact ever" an invalid state**, not a
degraded one.

**JetBrains is a live counter-signal to the current arxa design.** The self-hosted
floating License Server (FLS) "was discontinued on January 1, 2026" and instances are
being phased out; the replacement is cloud/on-prem **License Vault** in IDE Services.
Licensing remains **per-machine**: "if a single user runs multiple IDEs concurrently on
different machines, it requires a license per each machine." Notably, License Vault
"doesn't support and can't distribute expired or perpetual fallback licenses" — those are
assigned directly through JetBrains Account. (Grade A.)
<https://www.jetbrains.com/help/license_server/License_Server_discontinuation.html> ·
<https://www.jetbrains.com/help/license_server/getting_started.html>

Unity: named-user licensing plus a floating licensing server with borrow/check-out for
disconnected use — same shape, enterprise-flavoured. (Grade B; official pages, sparse.)
<https://docs.unity3d.com/Manual/LicenseOverview.html> ·
<https://docs.unity.com/licensing/en-us/manual/LicenseBorrow>

CLI sign-in (Copilot CLI, gh, and similar headless tools) is the OAuth 2.0 **Device
Authorization Grant**, RFC 8628, which GitHub implements explicitly "for apps that don't
have access to a web browser." (Grade A.)
<https://datatracker.ietf.org/doc/html/rfc8628> ·
<https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/authorizing-oauth-apps#device-flow>

---

## Q2 — Offline handling, heartbeat, revocation

**Concrete numbers exist only from Keygen.** (Grade A for these values; grade C for any
claim that they represent an "industry norm" — no survey data was found.)

- `heartbeatDuration` — seconds; **minimum 60**. No documented default value.
- `heartbeatCullStrategy` — default `DEACTIVATE_DEAD`; alternative `KEEP_DEAD`. Dead
  machines **fail validation** with code `HEARTBEAT_DEAD`.
- `heartbeatResurrectionStrategy` — default `NO_REVIVE`; opt-in resurrection windows
  starting at 1 minute.
- `heartbeatBasis` — `FROM_CREATION` vs `FROM_FIRST_PING`.
- `expirationStrategy` — default `RESTRICT_ACCESS`; the perpetual-fallback pattern (keep
  using what you have, lose access to releases published after expiry) is a **first-class
  documented option**, not a hack.
- `expirationBasis` default `FROM_CREATION`; `renewalBasis` default `FROM_EXPIRY`.
- Activation-abuse control: cap activations/deactivations per license token, "e.g. 10
  activations and 9 deactivations."

<https://keygen.sh/docs/api/policies/> · <https://keygen.sh/docs/api/machines/>

For genuinely offline use, Keygen's current recommendation is **cryptographic license
files** (checked-out, signed, optionally encrypted certificates with a TTL), *not* signed
license keys. Their stated reason is directly relevant to arxa: "the embedded datasets
within cryptographic keys are **immutable** … changing the datasets, e.g. extending a
license expiration or updating entitlements, requires generating a brand new license."
(Grade A.)
<https://keygen.sh/docs/choosing-a-licensing-model/offline-licenses/> ·
<https://keygen.sh/blog/announcing-cryptographic-license-files/>

**Uncertainty flag:** "30 days grace" (arxa's current value) has no documented vendor
source. It is convention, not standard. Keygen's mechanism is a *file TTL*, and TTL
length is left to the vendor. Treat any specific grace number as a product decision, not
a best practice.

---

## Q3 — Machine binding

**Fingerprint inputs (grade B — corroborated across vendors, no single canonical doc):**

| OS | Conventional source |
|---|---|
| macOS | `IOPlatformUUID` (IOKit registry) |
| Windows | `HKEY_LOCAL_MACHINE\...\Cryptography\MachineGuid` |
| Linux | `/etc/machine-id` or `/var/lib/dbus/machine-id`; DMI `product_uuid`, `board_serial` |

Practice is to **hash** the composite (SHA-256) rather than transmit raw identifiers, and
to generate-and-store a fallback UUID where the platform identifier is unavailable. MAC
addresses are widely deprecated as unstable/virtualisable.
<https://keygen.sh/docs/activating-machines/> ·
<https://netlicensing.io/wiki/faq-how-to-generate-machine-fingerprint>

Keygen's server-side controls (grade A, <https://keygen.sh/docs/api/policies/>):

- `machineUniquenessStrategy` — default `UNIQUE_PER_LICENSE`; `UNIQUE_PER_POLICY` is the
  documented way to stop trial-farming on one device.
- `machineMatchingStrategy` — fuzzy matching (e.g. `MATCH_ANY` on components) so a RAM
  upgrade doesn't invalidate a seat.
- `machineLeasingStrategy` — default `PER_LICENSE`, or `PER_USER`.
- `overageStrategy` — default `NO_OVERAGE`; overage allowances exist specifically for
  rolling-restart environments.
- `requireFingerprintScope` — forces every validation to be machine-scoped.

**Machine changes:** documented practice is self-service **deactivation to free a slot**,
with deactivation optionally disabled, plus activation/deactivation counters to detect
abuse. (Grade A.)

**Seats per licence: uncertainty flag.** Typical activation counts (2? 3?) come from
vendor pricing pages and EULAs, not engineering docs. No authoritative number was found.
JetBrains' documented stance is per-machine concurrency, which implies 1 concurrent seat
regardless of how many installs exist.

---

## Q4 — Anti-tamper reality check

**Documented facts (grade A):** Flutter/Dart obfuscation "hides function and class names
… replacing each symbol with another symbol." The docs then state plainly: obfuscation
"does *not* encrypt resources nor does it protect against reverse engineering. It only
renames symbols." And: "It is a **poor security practice** to store secrets in an app."
`--obfuscate --split-debug-info` is supported for `macos`, `windows`, `linux` targets
(among others). <https://docs.flutter.dev/deployment/obfuscate>

**Uncertainty flag — this is the weakest-sourced question in this report.** Two targeted
web searches on binary-tamper topics were refused by the search tool, and no
authoritative engineering write-up on Dart AOT gate-patching was retrieved. What follows
is grade **C** inference from architecture, not citation:

1. Any gate whose *decision* is computed locally from locally-held data is a branch that
   can be flipped. Ed25519 verification against an embedded public key is
   integrity-checking, not access control.
2. The accepted bar is therefore **relocating the value, not hardening the branch**: the
   server holds something the client cannot synthesise. Keygen's `strict` policy +
   fingerprint-scoped validation + short-TTL checkout is exactly this shape.
3. What genuinely is table stakes and cheap: compile out dev/env bypasses in release
   builds (a plaintext env bypass is not defeated by obfuscation — it is *documented* by
   it), sign and notarise the binary, ship `--obfuscate`, and treat all of it as
   friction/telemetry rather than a boundary.

**Do not claim** any of this makes the binary tamper-proof. It does not.

---

## Q5 — Supabase as the entitlement backend

**Uncertainty flag (grade B — documented absence):** there is **no first-party Supabase
guide for desktop/CLI licensing**. Every component below is documented; their composition
into a licensing system is not blessed by Supabase. Treat "Supabase licensing pattern" as
our design, not a cited one.

Documented primitives:

- **Sessions/JWTs.** Access tokens are "designed to be short lived, usually between 5
  minutes and 1 hour"; refresh tokens never expire but are single-use. Time-boxed
  sessions, inactivity timeout and single-session-per-user are Pro-plan-and-up features.
  <https://supabase.com/docs/guides/auth/sessions>
- **Asymmetric JWT signing keys + JWKS.** Public keys "can only be used to verify the
  signature … but not create new ones," validation is local and does not involve the Auth
  server, and rotation is zero-downtime. This is what makes offline-ish verification in a
  Dart client viable. <https://supabase.com/docs/guides/auth/signing-keys>
- **Custom Access Token Hook** — inject entitlement claims at token-issue time; required
  claims are fixed (`iss`, `aud`, `exp`, `iat`, `sub`, `role`, `aal`, `session_id`,
  `email`, `phone`, `is_anonymous`).
  <https://supabase.com/docs/guides/auth/auth-hooks/custom-access-token-hook>
- **Edge Function auth modes** — `'user'` (user JWT, RLS-scoped `ctx.supabase`),
  `'secret'` (service-to-service, `ctx.supabaseAdmin`), `'publishable'`, `'none'` for
  signed webhooks. <https://supabase.com/docs/guides/functions/auth>
- **Deep-link OAuth** — custom URL scheme registered in Auth URL configuration
  (`com.example://**`), `signInWithOAuth({ redirectTo, skipBrowserRedirect: true })`,
  then `setSession({ access_token, refresh_token })`. Documented for Flutter among other
  targets. <https://supabase.com/docs/guides/auth/native-mobile-deep-linking>

**Gap worth knowing before design lock (grade B):** Supabase Auth documents **no RFC 8628
device authorization grant**. A headless/SSH `arxa login` cannot use a standard device
code flow out of the box — it needs either loopback-redirect PKCE (browser on the same
machine) or a first-party paste-a-code exchange implemented in an Edge Function.

---

## Q6 — Stripe → entitlements → tokens

**Stripe Entitlements removes most of the mapping work (grade A).** Attach *features* to
*products*; on purchase Stripe fires
`entitlements.active_entitlement_summary.updated` carrying the customer's full, current
entitlement summary, and your app enables whatever appears under `entitlements.data`. On
cancellation **or automatic cancellation due to failed payments**, the same event fires
with the feature absent. Caveat: the summary webhook carries **a maximum of 10
entitlements**. <https://docs.stripe.com/billing/entitlements>

**Payment failure is dunning-first, not immediate cut (grade A).** Smart Retries reattempt
per a configured number of tries within 1 week / 2 weeks / 3 weeks / 1 month / 2 months;
**Stripe's recommended default is 8 tries within 2 weeks**. During this window the
subscription sits in `past_due` or `unpaid` depending on Dashboard failed-payment
settings; in `unpaid`, invoices keep generating in `draft` and collection pauses.
<https://docs.stripe.com/billing/revenue-recovery/smart-retries> ·
<https://docs.stripe.com/billing/subscriptions/overview>

Implication: the vendor-side dunning grace (~2 weeks) and the client-side offline grace
are **two different clocks**. Conflating them is the common design error.

---

## Recommended architecture for arxa

1. **Keep the Ed25519 verifier; demote it.** It becomes the *offline continuation*
   mechanism, not the gate. Supersedes `monetization-and-licensing.md` §3's
   "never phone home."
2. **Delete the plaintext env bypass from release builds** — compile-time excluded, not
   runtime-checked. Non-negotiable and independent of everything else.
3. **`arxa login`** → Supabase Auth with loopback-redirect PKCE (desktop) or
   deep-link (`arxa://auth-callback`) per Supabase's documented flow. Google/Apple ride
   on this for free. Add a paste-a-code Edge Function path for headless/SSH.
4. **Postgres schema:** `subscriptions` (Stripe mirror), `entitlements`
   (`user_id`, `feature`, `status`, `expires_at`), `machines`
   (`user_id`, `fingerprint_sha256`, `platform`, `activated_at`, `last_seen_at`,
   `deactivated_at`). RLS: users read their own rows; **only the service role writes**.
5. **`POST /activate` Edge Function** (`auth: 'user'`): takes a hashed fingerprint,
   enforces the seat cap, records the machine, returns an **entitlement token** — a JWT
   signed by an arxa-controlled key, claims `sub`, `fpr`, `feat: ["emit.scaffold"]`,
   `exp` ≈ 7 days, `nbf`. Cache it at `~/.arxa/entitlement.jwt`.
6. **`emit scaffold` gate:** verify the cached token locally against a pinned public key,
   require `fpr` to match the live fingerprint, require `exp` in the future. No network
   call on the hot path.
7. **Refresh, not heartbeat.** Silent refresh on any command when the token is inside its
   last 48 h. Offline continues until `exp`. This is Keygen's license-file model, not a
   ping loop — arxa is not a concurrency-limited product and does not need one.
8. **Seats: 3 activations, self-service deactivation, activation counter for abuse.**
   Fuzzy match on fingerprint components so hardware changes don't burn a seat. (Seat
   count is a product decision — no documented industry number backs "3".)
9. **Stripe webhook → `entitlements`** via an Edge Function (`auth: 'none'`, verify the
   Stripe signature). Prefer `entitlements.active_entitlement_summary.updated` over
   hand-mapping subscription statuses.
10. **Grace clocks, separated:** `past_due` keeps entitlements live for Stripe's full
    dunning window (default 8 tries / 2 weeks); `canceled` stops **token reissue**, and
    the already-issued ≤7-day token expires naturally. No mid-session revocation.
11. **Ship `--obfuscate --split-debug-info`, sign and notarise.** Friction and crash
    hygiene — explicitly not claimed as a security boundary.

---

## Open flags for the team lead

- **Degrade vs block.** `watermark.dart:16-17` states invalid/expired/none "never block
  emission." This architecture assumes *block* at `emit scaffold`. That contract
  inversion is a product decision this doc does not make. See
  [`paygate-hook-points.md`](./paygate-hook-points.md).
- **First owned trust surface.** `paygate-hook-points.md` records that no arxa-owned
  server exists and every outbound call is third-party. A Supabase Edge Function is the
  first arxa-controlled trust surface — it brings uptime, key-rotation and
  incident-response obligations that do not exist today. An offline path that survives
  Supabase being down is therefore mandatory, not a nicety.
- **Air-gapped users.** Steps 5–7 assume periodic connectivity. A genuinely air-gapped
  buyer needs a manual license-file checkout path (Keygen's model) or must be declared
  out of scope.
- **Q4 is under-sourced.** Two searches were refused by the tooling; the anti-tamper
  section is inference, grade C, and should not be cited as practice.
