# tools/verification

The tier suites that set a provider's `verification` field. **A tier is set only
by a suite that ran at that tier** (plan 13.3) — this directory is the only path
that writes the registry's `verification` values and the evidence ledger.

## The three tiers

| tier | question it answers | requirements | runnable in CI |
|---|---|---|---|
| **Tier 1** — port + scripted fake | *do we call the SDK correctly, and handle its failures?* | none | **yes** — no toolchain, no credentials, no device |
| **Tier 2** — simulator/emulator | UI, layout, flow wiring, seeded data | a simulator/emulator image | no — needs a host with the platform tooling |
| **Tier 3** — physical device | entitlements, certificates, real tokens | a physical device + real keys | no — mandatory before `device-verified` |

## Tier 1 — run it

```
python3 tools/verification/tier1.py --promote
```

On a green run this sets `verification = port-tested` for every provider whose
suite passed and records an evidence entry (suite path + content digest +
timestamp) in `evidence.json`. Re-running is idempotent: unchanged suite content
leaves both files stable. Without `--promote` the suites run but write nothing.

The pattern mirrors the deploy kit's `KitProcessRunner` / `ScriptedProcessRunner`:
each external SDK is invoked through a `ProcessRunner`; the suite injects a
`ScriptedRunner` that asserts the exact command shape and returns canned results.
No real SDK is installed, no network is touched.

Currently Tier-1-green (5): `payments/Stripe`, `payments/PayPal`,
`auth/Apple SignIn`, `auth/Google SignIn`, `auth/SeedAuthBackend`.

`SeedAuthBackend` is the exception — it has no external process, so its suite
tests the **real** backend (an in-memory seeded user store), not a scripted fake.
It was implemented first (13.7) because it unblocks the seeded-data story and
needs no device and no accounts.

## Tier 2 — simulator (env-blocked)

Not run in CI. To run a Tier-2 suite a developer needs a host with the platform
tooling and, depending on the flow, a signed-in account:

| flow | requirement |
|---|---|
| Apple Pay | simulator returns **dummy test cards** and bypasses real device checks |
| Sign in with Apple | an Apple ID signed into Simulator Settings, or it always fails |
| Google Sign-In (Android) | a **Play Services** image + the **debug keystore SHA-1** registered separately from release |

What Tier 2 **cannot** prove is recorded in `gates/advertise/README.md`. A
`sim-verified` tier is set by a Tier-2 suite writing here, the same way Tier 1
writes `port-tested`. **No simulator run has executed yet** — every simulator
tier is honestly absent until one does.

## Tier 3 — device (env-blocked, mandatory)

No provider reaches `device-verified` without a Tier-3 run on a physical device.
Stripe's own guidance: a **physical device with test keys is mandatory** before
trusting the integration. See `gates/advertise/README.md` for the full
device-only list.

## Sequence (13.8) — current status

| # | step | status |
|---|---|---|
| 1 | `verification` field + advertise gate | ✅ done |
| 2 | `SeedAuthBackend` to Tier 1 | ✅ done (port-tested) |
| 3 | ports for payments + auth to Tier 1 | ✅ done (Stripe, PayPal, Apple/Google signin → port-tested) |
| 4 | Stripe to Tier 3 | ⛔ env-blocked — physical device + Stripe test keys |
| 5 | auth providers to Tier 3 | ⛔ env-blocked — device + Apple/Google developer accounts |
| 6 | maps + Vercel last | ⛔ not started — neither blocks appbox; `Vercel` stays stub and is **not advertised** until its port lands |

Items 4–6 are recorded as the known remaining work. They are **not faked**: a
tier that has no suite run stays `stub` in the registry, and `gates/advertise`
rejects any offer of it.
