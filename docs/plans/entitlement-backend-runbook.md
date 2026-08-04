# Entitlement backend — deployment runbook

Status: **runbook, not code** (2026-08-05). The local half of D17/D18 —
`appboxd/lib/entitlement.dart` (offline JWT verification), the scaffold-boundary
assertion in `scaffoldMain` + `scaffoldGate`, and `appbox entitlement
status/verify` — is shipped. This document is the contract the hosted half
must implement so the two cannot drift. Source of decisions:
`docs/plans/monetization-and-entitlements.md` (D17–D20, D29–D33).

The golden rule: **the client verifier is the authority on the token format.**
Whatever this runbook and the deployed backend produce must verify against
`Entitlement.verify` in `appboxd/lib/entitlement.dart` — when in doubt, mint a
token and run `appbox entitlement verify <file>`.

---

## 1. The token contract (load-bearing, exact)

`POST /activate` returns a compact JWS (`header.payload.signature`, base64url —
padded or unpadded both verify) cached by the client at
`~/.appbox/entitlement.jwt`.

**Header:**

```json
{ "alg": "EdDSA", "typ": "JWT" }
```

`alg` MUST be `EdDSA`. The verifier rejects every other value, including
`none` (algorithm-confusion guard). `typ` is ignored.

**Claims:**

| claim | type | required | meaning |
|---|---|---|---|
| `sub` | string, non-empty | yes | the Supabase user id |
| `fpr` | string, 64-char hex | yes | sha256 hex of the machine fingerprint the token is bound to |
| `feat` | array of strings | yes | MUST contain `"emit.scaffold"` (D17's scaffold entitlement) |
| `nbf` | integer, epoch seconds | yes | not-before; tokens issued future-dated are rejected |
| `exp` | integer, epoch seconds | yes | expiry; issue with ≈ 7 days (`nbf + 7*86400`) |
| `iat` | integer, epoch seconds | optional | issued-at; ignored by the verifier |

**Signature:** Ed25519 over the exact ASCII bytes of `<header>.<payload>` as
they appear in the compact serialization. The verifier never re-encodes —
whitespace or key-order changes between signing and caching break (or forge)
nothing, because verification covers the cached bytes verbatim.

**Signing key:** the appbox-owned Ed25519 issuer keypair. The public half is
embedded in the client as `Entitlement.publicKey`
(`appboxd/lib/entitlement.dart`). **The private half must never enter this
repo.** What ships today is a DEV keypair (its private half lives in
`appboxd/test/entitlement_fixture.dart`, marked dev-only) so the whole flow is
exercisable; replace the constant with the production public key before the
first paid release — nothing else in the verification path changes.

**Verdict semantics the client applies** (mirror of `Entitlement.verify`):

| verdict | condition | unlocks scaffold? |
|---|---|---|
| `valid` | signature ok, claims well-formed, `nbf <= now <= exp`, `fpr` == this machine | yes |
| `grace` | authentic + machine-bound, `exp < now <= exp + 30 days` | yes (offline continuation) |
| `expired` | authentic + machine-bound, past grace | no |
| `invalid` | forged/tampered/wrong key/malformed/`alg != EdDSA`/`nbf` in future/missing `emit.scaffold`/`fpr` for another machine/local fingerprint undeterminable | no |
| `none` | no token file | no |

The 30-day offline-continuation grace is client-side and deliberate: Supabase
downtime must never block a paying user. It is **separate from Stripe's
dunning clock** (~8 retries / 2 weeks) by decision — do not try to sync them.

**Machine fingerprint** (hashed client-side, never transmitted raw): macOS
`IOPlatformUUID` (`ioreg -rd1 -c IOPlatformExpertDevice`), Windows
`MachineGuid` (`HKLM\SOFTWARE\Microsoft\Cryptography`), Linux
`/etc/machine-id` (fallback `/var/lib/dbus/machine-id`). `fpr` =
lowercase sha256 hex of the raw id string.

## 2. Supabase schema

Three tables (D18). RLS: users read their own rows; **all writes are
service-role-only** (the Edge Functions and the Stripe webhook, never the
client).

```sql
-- Stripe mirror; the webhook is the only writer.
create table subscriptions (
  user_id              uuid primary key references auth.users,
  stripe_customer_id   text not null,
  stripe_subscription_id text not null,
  tier                 text not null check (tier in ('pro', 'scale')),
  status               text not null,  -- Stripe's, verbatim
  current_period_end   timestamptz not null,
  updated_at           timestamptz not null default now()
);

-- What the user may do. One row per (user, feature).
create table entitlements (
  user_id    uuid not null references auth.users,
  feature    text not null,            -- 'emit.scaffold' today
  status     text not null check (status in ('active', 'past_due', 'canceled')),
  expires_at timestamptz not null,
  primary key (user_id, feature)
);

-- Seat cap: 3 machines per user, self-service deactivation.
create table machines (
  user_id           uuid not null references auth.users,
  fingerprint_sha256 text not null,    -- the fpr claim; hashed, never raw
  platform          text not null,     -- 'macos' | 'windows' | 'linux'
  activated_at      timestamptz not null default now(),
  last_seen_at      timestamptz not null default now(),
  deactivated_at    timestamptz,       -- null = active seat
  primary key (user_id, fingerprint_sha256)
);

alter table subscriptions enable row level security;
alter table entitlements enable row level security;
alter table machines enable row level security;
-- read-own-rows policies on all three; no insert/update/delete policies —
-- the service role bypasses RLS for writes.
```

## 3. `POST /activate` Edge Function

Request (authenticated — Supabase Auth JWT in the `Authorization` header):

```json
{ "fpr": "<sha256 hex of the machine fingerprint>", "platform": "macos" }
```

Logic, in order — every step fails closed (4xx with an honest error, never a
token):

1. Resolve the user from the auth JWT.
2. Require an `active` (or `past_due` inside Stripe's retry window — mirror
   the `entitlements.status`) row for feature `emit.scaffold` with
   `expires_at > now()`. No row → 402.
3. Seat cap: count `machines` rows with `deactivated_at is null`. If this
   `fpr` is already active, refresh `last_seen_at` and re-issue. Otherwise
   require < 3 active seats; at cap → 409 naming self-service deactivation
   (`DELETE /machines/:fpr`, same function router — sets `deactivated_at`).
4. Insert/refresh the machine row.
5. Mint the token per §1: `sub` = user id, `fpr` = the request fingerprint,
   `feat = ["emit.scaffold"]`, `nbf = now`, `exp = now + 7 days`, signed with
   the issuer private key (Supabase secret, never in the repo).

Response: `{ "token": "<compact JWS>" }`. The client writes it to
`~/.appbox/entitlement.jwt`.

Known abuse gap (carried from the plan's risks): the 3-seat cap with
self-service deactivation is the only control; rapid activate/deactivate
cycling is unaddressed (no `machineUniquenessStrategy` equivalent adopted).
Log activations; decide rate-limiting before launch, not after.

## 4. Auth flow (client → Supabase)

- Desktop: Supabase Auth with **loopback-redirect PKCE**.
- Mobile: `appbox://auth-callback` deep-link.
- Headless/SSH: paste-a-code path against the same Edge Function router.
- There is no Supabase device-code flow — documented gap, do not design
  against one.
- `appbox login` (workstream 2) stores tokens in the OS keychain vault,
  reusing D14's OAuth-first account-connection pattern. Not built yet; this
  runbook does not ship a client.

## 5. Stripe sync

- Checkout + pricing page per the resolved tiers: Free (forever; design +
  eject + BYO-LLM, unlimited, anonymous), Pro (~$20–40/seat/mo, unlocks
  `emit.scaffold`), Scale ($149/mo/org, unlimited seats, 3 released apps,
  +$49/app/mo beyond 3, 50k bundled patch installs, overage $1.50/2,500).
- A Stripe webhook (Entitlements/Subscription events) is the **only** writer
  of `subscriptions`/`entitlements`, mapping the Stripe entitlement
  `emit.scaffold` onto the table row with `expires_at = current_period_end`.
- Vendor dunning (~8 retries / 2 weeks) lives in Stripe and stays there —
  it is deliberately NOT the client's offline-grace clock.

## 6. Refresh & offline behavior (client, workstream 4 remainder)

Already shipped locally: offline verification, machine binding, 30-day
grace. Still to build (needs this backend): silent background refresh of the
cached token inside its last 48h (Keygen's license-file model — no
heartbeat), and `appbox login` itself. Refresh failures must be silent and
never destructive: a failed refresh leaves the cached token in place and the
offline-verdict semantics decide.

## 7. Pre-ship obligations (from the plan's risks — owning these is part of deploy)

- **Key management.** The issuer keypair is appbox's first owned trust
  surface: rotation procedure, compromise response, and uptime ownership
  named before the first paid release.
- **Dev key swap.** Replace `Entitlement.publicKey` with the production
  public key; regenerate test fixtures' expectations if any pin it (none do —
  fixtures carry their own dev seed). Also delete `_devSeed` / `mint --dev`
  from `lib/entitlement_cli.dart` and flip `test/release_gate_test.dart`
  (the release-gate checklist artifact — it passing means the dev keypair is
  still embedded and shipping).
- **Air-gapped buyers are unaddressed** (open question in the plan): a
  genuinely offline-forever customer needs a manual license-file checkout
  path or an explicit out-of-scope declaration. Decide before launch.
- **Shorebird figures** (D33): confirm real per-tier console prices — current
  numbers are aggregator-sourced.

## 8. What the old licence became

The Ed25519 `licence.json` (P1/P2, `appbox-memory-and-payment.md`) is
**retired, not demoted, in the client**: `licence.dart`, `licence_tool.dart`,
`watermark.dart`, the `appbox watermark` command, and the
`APPBOX_DEV_LICENCE` bypass are deleted. The entitlement JWT IS the
signed+TTL offline-continuation artifact the plan demotes the licence to —
nothing else issues or consumes licence files, so keeping the parser was dead
code. The deploy gate keeps only its pipeline-state contract
(target/version/account); the payment boundary lives at scaffold.
