# Making the stubs real — and provable on simulators

Inventory in [`../research/stub-inventory.md`](../research/stub-inventory.md).
This is the plan to close it, and the honest ceiling on what a simulator can
prove.

## The core problem is not the stubs — it's that "wired" is a grep

Today a provider's status lives in the *message of the exception it throws*:
`UnimplementedError('StripePaymentsProvider is a stub (phase-later)')`. Nothing
queryable. `settings.kits` cannot render truth, and nothing stops the UI
offering a target that throws.

**Fix first, before any provider work:** make the tier a registry field.

```
verification: stub | port-tested | sim-verified | device-verified
```

Then one gate does the work forever: **no provider may be advertised above its
recorded tier.** Michelle never meets an `UnimplementedError` the UI offered
her — which is her stated abandon condition.

## The three test tiers

### Tier 1 — port + scripted fake (no toolchain, runs in CI)

The kit already proves this pattern works: `stacked_kit_deploy` runs every
external CLI through `KitProcessRunner`, so `ScriptedProcessRunner` asserts
command shape **with no fastlane, no shorebird, no credentials**.

Apply the same port to payments and auth. Tier 1 answers *"do we call the SDK
correctly, and handle its failures?"* and it answers it on every commit.

### Tier 2 — simulator / emulator

UI, layout, flow wiring, seeded data. **What it cannot prove:**

| flow | simulator reality |
|---|---|
| **Apple Pay** | the sheet appears and returns **dummy test cards**; the simulator **bypasses real device checks**. Success here says nothing about merchant ID, CSR/certificate, or entitlement |
| **Sign in with Apple** | requires an Apple ID signed into Simulator Settings or it *always* fails; a missing "Sign in with Apple" capability **fails with no visual indication** |
| **Google Sign-In (iOS Sim)** | generally works — it uses `ASWebAuthenticationSession`, not a native picker |
| **Google Sign-In (Android Emu)** | needs a **Play Services** system image (AOSP has none) and the **debug keystore SHA-1 registered separately** from release |
| **Sign in with Apple (Android)** | a *web redirect* flow — emulator works, but needs a backend endpoint and a manifest intent-filter |

### Tier 3 — physical device

Entitlements, certificates, real tokens. Stripe's own guidance is explicit:
use the simulator for payment-sheet **UI iteration**, and treat **a physical
device with test keys as mandatory** before trusting the integration.

Also device-only: Apple's **"hide my email"** returns a random forwarding
address rather than the real Apple ID email — a backend behaviour you cannot
observe on a simulator.

**No provider reaches `device-verified` without this tier. There is no
shortcut, and pretending otherwise is the stale-green pattern with money
attached.**

## Per-stub plan

| kit / provider | now | target | notes |
|---|---|---|---|
| `payments` / Stripe | stub | **device-verified** | kit's own TODO says `flutter_stripe`. Needs Merchant ID + CSR — **one CSR issues exactly one certificate**, and changing Merchant ID means a new CSR |
| `payments` / PayPal | stub | port-tested | Braintree / Orders v2. Lower priority — Stripe first |
| `payments` / Apple Pay | wired | device-verified | already the only wired path; still unproven above Tier 2 |
| `auth` / Apple sign-in | stub | device-verified | capability failure is **silent** — Tier 1 must assert the capability exists, not just the call shape |
| `auth` / Google sign-in | stub | sim-verified → device | config placement (`google-services.json`, `GoogleService-Info.plist`) is a frequent **silent** failure |
| `auth` / `SeedAuthBackend` | stub (phase-4) | **port-tested, first** | this one blocks the seeded-data story the product promises, and needs no device at all |
| `maps` / OSM, Mapbox | stub | sim-verified | `flutter_map ^8.x`, `mapbox_maps_flutter ^2.x` |
| `deploy` / vercel | stub | port-tested | trivial under the existing runner port; **do not advertise until then** |

## Sequence

1. **`verification` field + the advertise-gate.** Cheapest, and it makes every
   later step honest by default.
2. **`SeedAuthBackend`.** No device, no accounts, unblocks seeded data — and
   appbox's own showcase depends on it.
3. **Ports for payments and auth** (Tier 1). Now the SDK calls are asserted in
   CI forever.
4. **Stripe to Tier 3.** appbox's own licensing needs it; dogfooding forces
   it to be real.
5. **Auth providers to Tier 3.**
6. **Maps, vercel** — lowest priority; neither blocks appbox itself.

## The rule to write into the gate

> A provider's `verification` tier is set **only** by a suite that ran at that
> tier. Tier 3 cannot be claimed by a simulator run, and no tier may be set by
> editing the registry by hand.

Same standard as `structure.json`: the field is *evidence*, not a label.
