# Paygate hook points in appbox

## Summary

The brief's premise — "confirm absence if none" — is **wrong**. appbox already ships a
complete monetization system: an Ed25519-signed, fully-offline licence
(`appboxd/lib/licence.dart`), a five-state verdict with a 30-day grace period, and an
enforced paywall. The paywall is **already installed at first deploy**
(`appboxd/lib/gate_deploy.dart:9`), fail-closed, and it is the first thing `deployGate`
checks (`:23-28`).

The real finding is a **boundary mismatch**, not a greenfield. Implemented boundary =
free through scaffold+build, paid at deploy. Requested boundary = free through design,
paid from scaffold onward. Moving it means adding licence assertions to a scaffold path
that today has **zero** licence references (`gate_scaffold.dart`, `phases.dart`,
`scaffold_cli.dart` — 0 matches each).

There is also a **philosophy conflict** the team lead must resolve, not me:
`watermark.dart:16-17` states invalid/expired/none "never block emission" — the shipped
unpaid experience is *degrade* (watermark the output), not *block*. Gating scaffold
inverts that contract.

No appbox-owned server exists. Every outbound call is third-party. Any online
entitlement check requires new infrastructure that does not exist today.

---

## Q1 — Existing monetization/entitlement code: PRESENT, not absent

| Component | Citation |
|---|---|
| Licence value type + status enum | `appboxd/lib/licence.dart:49` — `enum LicenceStatus { valid, expired, grace, invalid, none }` |
| Verdict class | `appboxd/lib/licence.dart:51` — `class LicenceVerdict` |
| Grace period | `appboxd/lib/licence.dart:81` — `static const gracePeriod = Duration(days: 30)` |
| Embedded public key | `appboxd/lib/licence.dart:83-90` — "The appbox licence PUBLIC key (Ed25519, 32 bytes)" |
| Offline verification | `appboxd/lib/licence.dart:96` — `static LicenceVerdict verify(List<int> fileBytes, {DateTime? now})` |
| File-based verification | `appboxd/lib/licence.dart:172` — `static LicenceVerdict verifyFile(String path, ...)` |
| Signature scheme | `appboxd/lib/licence.dart:2` — "Ed25519-signed licence file, verified fully offline by appboxd" |
| Canonical signing bytes | `appboxd/lib/licence.dart:23-26` — payload re-encoded sorted-keys/no-whitespace/UTF-8 |
| Ed25519 implementation | `appboxd/lib/ed25519.dart` (imported at `licence.dart:47`) |
| Tier plans | `appboxd/lib/licence.dart:14` — `"tier": "annual"` \| `"perpetual"` |
| Free/paid tier watermarking | `appboxd/lib/watermark.dart:5-6, :16-17, :32-33, :54-59` |
| Watermark string | `appboxd/lib/watermark.dart:33` — `'Built with appbox (free tier) — https://appbox.dev'` |
| Provenance manifest | `appboxd/lib/watermark.dart:36, :99, :137` — `.appbox-provenance.json` `{tier, ts, files[]}` |
| Tier resolution from licence | `appboxd/lib/watermark.dart:101-106` — valid/grace → paid, else free |
| Licence CLI | `appboxd/bin/licence_tool.dart:37, :39` — `status`, `verify` subcommands only |
| Watermark CLI flag | `appboxd/bin/appbox.dart:695-704` — `appbox watermark <rootDir> [--licence <path>]` |
| Tests | `appboxd/test/watermark_test.dart:35, :67` — free-tier watermark, paid-tier clean |

### Licence payload shape (`appboxd/lib/licence.dart:10-19`)

```json
{ "payload": { "email", "tier", "issued", "expires", "licence_id" }, "signature": "<b64url Ed25519>" }
```

**Critical gap: no machine/host/seat binding.** The payload carries `email` and
`licence_id` but no hardware fingerprint. One licence file copies freely to unlimited
machines. This ceilings the tamper resistance of *every* enforcement point below,
including the deploy gate that ships today.

### Licence file discovery (`appboxd/lib/gate_deploy.dart:145-152`)

Mirrors `licence_tool`'s `_defaultLicencePath`: `~/.appbox/licence.json`, then
`<repoRoot>/pipeline/state/licence.json`. First existing candidate wins.

### Dev bypass

`appboxd/lib/gate_deploy.dart:15` — "APPBOX_DEV_LICENCE=1 is the documented dev/dogfood
bypass"; implemented at `:97` as a plaintext `Platform.environment` check returning
`okLine: 'licence: DEV BYPASS ...'` (`:100`). A one-word env var defeats the shipped
paywall.

---

## Q2 — Paywall hook points for "scaffold onward"

### Where the paywall sits today

`appboxd/lib/gate_deploy.dart:9-11` — "the paywall sits at first deploy … failing
CLOSED. A licence failure is never [a sarif finding]". `deployGate` runs the licence
assertion **first** (`:23-24`) and returns `GateResult.fail('deploy: HALTED — §17
licence assertion failed (see above).', licence.failLines)` (`:26-28`). Assertion helper:
`:94` — `({bool passed, String okLine, List<String> failLines}) _licenceAssertion(...)`,
calling `Licence.verifyFile(path)` at `:109`.

### Scaffold-side choke points (all currently unguarded)

`grep -c licence` returns **0** for `gate_scaffold.dart`, `phases.dart`, and
`scaffold_cli.dart`.

| # | Choke point | Citation | Entitlement check shape | Bypassable? |
|---|---|---|---|---|
| 1 | `scaffoldGate(ctx)` gate dispatch | `appboxd/bin/appbox.dart:352-353` — `case 'scaffold': return scaffoldGate(ctx);` | Mirror `gate_deploy.dart:23-28`: licence assertion first, `GateResult.fail` on miss | **Yes** — only guards the *gate*, not the emitter |
| 2 | `scaffoldMain(rest)` emitter | `appboxd/bin/appbox.dart:606-607` — `case 'scaffold': exit(scaffoldMain(rest));` | Assert inside `scaffoldMain` before any file write | Harder — this is the real `appbox emit scaffold` work entry |
| 3 | Phase declaration | `appboxd/lib/phases.dart:17` — `'scaffold'` in phase list; `:58` — `'scaffold': ['scaffold', 'coverage']` | Phase-transition guard on entering `scaffold` | **Yes** — phases.dart is a declarative phase/gate map, not an execution funnel |
| 4 | Deploy gate (existing) | `gate_deploy.dart:23-28` | Already implemented | Only by `APPBOX_DEV_LICENCE=1` |

**Bypass analysis.** Checking at #1 or #3 alone is decorative: `phases.dart` declares
which gates belong to which phase but does not execute scaffolding, and the gate is
separable from the emitter. A caller can invoke `appbox emit scaffold` (#2) and never
touch `scaffoldGate`. The only defensible single insertion is **inside `scaffoldMain`**,
before it writes output. Even then, appbox ships as source-available Dart the user runs
locally — any check is removable by editing and recompiling. Enforcement here is a
speed bump, not a boundary.

---

## Q3 — The free web path (`appbox design eject`)

`design_tools.dart` contains **0 occurrences** of `scaffold`, `deploy`, or `licence`
(`grep -c` = 0). The design side is fully independent of the paid-side machinery.

- Eject walks the artifact directory and rewrites files in place:
  `appboxd/lib/design_tools.dart:280` (`var d = Directory(dir);`), `:297`
  (`List<File> _walk(Directory d)`), `:310` (`for (final f in _walk(Directory(artifactDir)))`).
- External dependencies are CDN/registry only: `:948` — `https://cdn.jsdelivr.net/npm`,
  `:949` — `https://registry.npmjs.org`.
- `appbox design serve` lives in `appboxd/lib/design_server.dart` (file watchers at
  `:210-211`) and imports nothing from the build/deploy path.

**Conclusion:** free = intake + design + eject + serve is cleanly severable today. It
needs no new isolation work.

---

## Q4 — Architecture reality check: no server-side component

Read in full: `config/appbox.config.json` (15 lines). Contains `version`, `targets`,
`viewports`, `viewportClasses`, `prototypeServer` (`{"host": "127.0.0.1", "port": 0}` —
**loopback only**), `prototypeRuntime`, `kit` (`repo`/`sha`, both empty), `escalationLimit`,
`dependencyMode`. **No** url, endpoint, telemetry, or account field.

`config/model-fabric.json` hosts are all third-party inference APIs called with the
*user's own keys*: `https://api.anthropic.com`, `https://api.deepseek.com/anthropic`,
`https://api.deepseek.com/v1`, `https://api.moonshot.ai/anthropic`,
`https://api.moonshot.ai/v1`, `https://api.openai.com/v1`, `https://api.x.ai/v1`,
`https://api.z.ai/api/paas/v4`, `https://generativelanguage.googleapis.com/v1beta/openai/`.

Other outbound references in `appboxd/`: OSM/Mapbox tiles
(`appboxd/lib/tier1.dart:468, :501`), jsdelivr/npm (`design_tools.dart:948-949`), and a
DevTools protocol doc comment (`cdp.dart:11`).

`https://appbox.dev` appears **only** as a watermark string literal
(`watermark.dart:33`) — it is never fetched.

`appboxd/bin/licence_tool.dart` exposes only `status` (`:37`) and `verify` (`:39`) — no
issuance, no signing, no network. Licence *signing* (the private key) lives outside this
repo.

**Conclusion: there is no appbox-owned endpoint, no update check, and no telemetry.**
Verification is 100% offline by design. Online entitlement checks, seat revocation, and
usage metering would all require new infrastructure that does not exist today.

---

## Q5 — Project/user identity

**No machine identity exists.** A grep of `appboxd/lib/secure_store.dart` for `uuid`,
`machineId`, `deviceId`, `userId`, and `account` returned **nothing**.

The only user-linked identifiers are the `email` and `licence_id` fields inside the
signed licence payload (`licence.dart:11, :15`) — self-asserted at issuance, unverified
at runtime, and not bound to hardware.

Available-but-unused primitives:

- `appboxd/lib/secure_store.dart:34` — `class SecureStore`
- `appboxd/lib/secure_store.dart:131` — `class SealedFileVault implements Vault`
- `:88` — encrypts and writes an `ABX1` envelope at mode `0600`
- `appboxd/lib/crypto_aead.dart` — XChaCha20-Poly1305 seal (`:14`), `sha256` (`:78`),
  `hmacSha256` (`:146`), `pbkdf2HmacSha256` (`:164`)

State lives in `pipeline/state/` (`default.state.json`, `default.intake.json`, plus
schemas) — project state, not identity.

---

## Candidate enforcement points, ranked by tamper resistance

All rankings are **capped by two structural facts**: the licence has no seat binding
(copies freely), and appbox executes locally as user-modifiable Dart. Nothing here is
strong against a determined user; the question is only how much friction each adds.

1. **Server-side issuance of the paid artifact** — *does not exist; highest ceiling.*
   Requires new infrastructure (Q4). If deploy credentials or a build service were
   brokered remotely, no local edit could bypass them. This is the only option that is
   genuinely tamper-*resistant* rather than tamper-*evident*.
2. **`scaffoldMain` (`appbox.dart:606-607`), assertion before first file write** — best
   available local point for the requested boundary. Sits in the execution path, not the
   gate path, so it cannot be skipped by invoking the emitter directly.
3. **Existing deploy-gate assertion (`gate_deploy.dart:23-28`)** — proven, fail-closed,
   already shipped. Weakened by `APPBOX_DEV_LICENCE=1` (`:97`); resistance rises
   immediately if that env bypass is compiled out of release builds.
4. **`scaffoldGate` (`appbox.dart:352-353`)** — cheap and consistent with existing gate
   conventions, but guards only the gate. Bypassed by calling the emitter (#2). Useful
   as a *second* layer, not as the primary.
5. **Watermark/provenance degradation (`watermark.dart:54-59`)** — already shipped and
   matches the codebase's stated philosophy (`:16-17`, never blocks emission). Trivially
   strippable, but it is *tamper-evident*: the `.appbox-provenance.json` sha256 manifest
   (`:137-142`) makes removal detectable downstream.
6. **`phases.dart:17, :58` phase-transition guard** — lowest. Declarative phase/gate
   mapping with no execution funnel; editing one list entry disables it.

### Decision the team lead owns

Gating scaffold **contradicts** the shipped degrade-don't-block contract
(`watermark.dart:16-17`). Two coherent options, and they should not be blended silently:

- **Keep degrade:** free tier scaffolds and builds freely but every emitted file carries
  the watermark; paid removes it. Preserves the existing philosophy and needs no new code.
- **Move to block:** insert the assertion at `scaffoldMain`. Delivers the requested
  free-design/paid-build split, but rewrites the product's stated contract and — absent
  seat binding and any server — is bypassable by one env var, one file copy, or one
  source edit.
