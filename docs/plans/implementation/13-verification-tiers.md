# 13 — Verification tiers: stop letting "wired" be a grep

**Goal.** A provider's real status becomes a queryable fact, and nothing can be
offered above the tier it has actually passed.

**Blocks:** 11 (advertising), 14. **Depends on:** 03.

Full context: [`../stub-remediation.md`](../stub-remediation.md).

## The problem

Status currently lives in the **message of the exception it throws**:
`UnimplementedError('StripePaymentsProvider is a stub (phase-later)')`. Nothing
queryable. The UI cannot render truth, and nothing stops it offering a target
that throws — which is Michelle's stated abandon condition.

## Steps

- [x] **13.1** Add `verification` to every provider entry in the vendored kit
      registry: `stub | port-tested | sim-verified | device-verified`.
- [x] **13.2** Add the **advertise gate**: no provider may be offered by any
      surface above its recorded tier. One assertion, applied forever.
- [x] **13.3** Write the rule into the gate itself:

      > A `verification` tier is set **only** by a suite that ran at that tier.
      > Tier 3 cannot be claimed by a simulator run, and no tier may be set by
      > editing the registry by hand.

      Same standard as `structure.json`: the field is **evidence**, not a label.
- [x] **13.4** Implement **Tier 1** for payments and auth — a process/SDK port
      plus a scripted fake, mirroring the deploy kit's runner. Runs in CI with
      no toolchain, no credentials, no device.
- [x] **13.5** Set up **Tier 2** runs. Record what the tier cannot prove, in the
      gate's README so nobody re-learns it:
      - **Apple Pay**: the sheet appears and returns **dummy test cards**; the
        simulator **bypasses real device checks**. Says nothing about merchant
        ID, CSR/certificate, or entitlement.
      - **Sign in with Apple**: needs an Apple ID signed into Simulator
        Settings or it *always* fails; a missing capability **fails with no
        visual indication**.
      - **Google Sign-In (Android emulator)**: needs a **Play Services** system
        image (AOSP has none) and the **debug keystore SHA-1 registered
        separately** from release.
- [x] **13.6** Define **Tier 3** as device-only and mandatory before
      `device-verified`. Stripe's own guidance: simulator for payment-sheet UI
      iteration, **physical device with test keys mandatory** before trusting
      the integration. Note that Apple's "hide my email" returns a random
      forwarding address — a backend behaviour invisible on a simulator.
- [x] **13.7** Implement `SeedAuthBackend` **first** among the stubs. It needs
      no device and no accounts, and it unblocks the seeded-data story the
      product promises.
- [x] **13.8** Sequence the rest: ports for payments and auth → Stripe to
      Tier 3 (arxa's own licensing needs it) → auth providers to Tier 3 →
      maps and vercel last.

## Done-when

1. Every provider carries a `verification` tier.
2. The advertise gate **fails** when a surface offers a `stub`-tier provider.
3. Hand-editing a tier in the registry is rejected.
4. Tier 1 suites for payments and auth run green **with no toolchain**.
5. `SeedAuthBackend` works and the showcase seeded data depends on it.
6. Each tier's README states what that tier cannot prove.
