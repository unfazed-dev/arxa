# advertise

The one gate that stops a surface offering a provider above its recorded
verification tier. **Michelle never meets an `UnimplementedError` the UI offered
her — which is her stated abandon condition.**

## What it asserts (13.2)

One assertion, applied forever:

> **No provider may be offered by any surface above its recorded tier.**

Concretely the gate fails when:

1. **A stub is offered.** A provider whose recorded `verification` is `stub` may
   not appear in any surface's `offers` — at any tier. A stub is displayed and
   labelled (settings.kits does this), never offered as available.
2. **An offer exceeds the recorded tier.** A surface offering a provider at
   `device-verified` while the registry records `port-tested` fails.

## The rule written into the gate (13.3)

> A provider's `verification` tier is set **only** by a suite that ran at that
> tier. Tier 3 cannot be claimed by a simulator run, and no tier may be set by
> editing the registry by hand.

The field is **evidence**, not a label — the same standard as `structure.json`.
The gate enforces this by cross-checking every non-`stub` tier against the
evidence ledger (`tools/verification/evidence.json`), which is written **only**
by a tier suite. The gate itself never writes the ledger.

- Bump a tier in the registry by hand → the ledger has no matching record →
  **FAIL** ("a tier is set only by a suite that ran; hand-edit rejected").
- Edit the suite file after a tier was set → the ledger's content digest no
  longer matches → **FAIL** ("re-run the suite to re-record evidence").
- Point evidence at a suite path that does not exist → **FAIL** ("stale or
  forged").

## Inputs

| file | role |
|---|---|
| `tools/vendor/kit_registry/kit-registry.json` | the recorded tier per provider (the claim) |
| `tools/verification/evidence.json` | the ledger of suites that ran (the proof) |
| `gates/advertise/offers.json` | what each surface offers, at what tier |

Run:

```
python3 gates/advertise/advertise.py
```

## The tiers

| tier | meaning | set by |
|---|---|---|
| `stub` | no suite has run; the provider throws or is unproven | default |
| `port-tested` | the SDK/port call shape is asserted in CI against a scripted fake, with **no toolchain, no credentials, no device** | a Tier-1 suite (`tools/verification/`) |
| `sim-verified` | the flow runs on a simulator/emulator | a Tier-2 suite |
| `device-verified` | the flow runs on a physical device with real keys/entitlements | a Tier-3 suite |

## What Tier 2 CANNOT prove (13.5)

Recorded here so nobody re-learns it. A `sim-verified` tier is **not** a green
light to ship — it proves UI/flow wiring and seeded data only.

| flow | simulator reality |
|---|---|
| **Apple Pay** | the sheet appears and returns **dummy test cards**; the simulator **bypasses real device checks**. Says nothing about merchant ID, CSR/certificate, or entitlement. |
| **Sign in with Apple** | requires an Apple ID signed into Simulator Settings or it *always* fails; a missing "Sign in with Apple" capability **fails with no visual indication**. |
| **Google Sign-In (iOS sim)** | generally works — it uses `ASWebAuthenticationSession`, not a native picker. |
| **Google Sign-In (Android emu)** | needs a **Play Services** system image (AOSP has none) and the **debug keystore SHA-1 registered separately** from release. |
| **Sign in with Apple (Android)** | a *web redirect* flow — emulator works, but needs a backend endpoint and a manifest intent-filter. |

## Tier 3 — device-only, mandatory (13.6)

Entitlements, certificates, real tokens. **No provider reaches
`device-verified` without a Tier-3 run on a physical device. There is no
shortcut** — pretending otherwise is the stale-green pattern with money
attached.

- **Stripe**: Stripe's own guidance is explicit — use the simulator for
  payment-sheet **UI iteration**, and treat **a physical device with test keys
  as mandatory** before trusting the integration.
- **Apple "hide my email"**: returns a random forwarding address rather than the
  real Apple ID email — a backend behaviour you cannot observe on a simulator.

## Sequence (13.8)

1. `verification` field + this gate (cheapest; makes every later step honest).
2. `SeedAuthBackend` to Tier 1 — no device, no accounts, unblocks seeded data.
3. Ports for payments + auth to Tier 1 (now the SDK calls are asserted in CI).
4. **Stripe to Tier 3** — app_box's own licensing needs it; dogfooding forces it.
5. Auth providers to Tier 3.
6. Maps + Vercel last — neither blocks app_box itself.

Steps 1–3 are implemented in this plan. Steps 4–6 are **env-blocked** (physical
device, merchant accounts, credentials) and recorded as the known remaining
work — they are not faked.
