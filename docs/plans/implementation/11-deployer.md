# 11 — `appbox-deployer` and gate 3

**Goal.** Ship through the already-wired deploy kit, behind the strictest human
gate in the product.

**Blocks:** 14. **Depends on:** 03, 04.

## Source — the work is done

`stacked_kit/deploy` is **pure Dart and standalone** (*"no flutter, stacked, or
stacked_kit dependency"*), registry `phase: stable`, with a
`bin/stacked_kit_deploy.dart` entry point and a `doctor(config)` preflight.

| target | status |
|---|---|
| `fastlane-android` / `fastlane-ios` | **wired** |
| `shorebird-release` / `shorebird-patch` | **wired** |
| `cloudflare-pages` | **wired** |
| `vercel` | **stub — throws `UnimplementedError`** |

**Why this is the right integration:** external CLIs run through a
`KitProcessRunner` port, so a scripted runner asserts **every command shape with
no toolchain in CI**. A deploy stage normally cannot be self-tested — no
credentials, no signing identity, no shorebird install. This one can.

## Steps

- [x] **11.1** Wire `skills/appbox-deployer/` over the vendored deploy kit.
      Registry says `hasSkill: false` for every kit — this is the first phase
      skill of its kind, so there is no in-kit prior art to copy. Follow the
      stage contract: one module, a self-test, JSON emit.
- [x] **11.2** Surface only targets whose `verification` tier permits it
      (plan 13). **Do not advertise `vercel`** while it throws.
- [x] **11.3** Run `doctor(config)` as preflight. It is **not** the gate —
      preflight reports readiness; the gate must assert a **value**.
- [x] **11.4** Implement **gate 3** in `gates/deploy/`. It names **target,
      version and account** and requires the person to confirm that exact
      triple. Every other gate is a read-only assertion; this one writes to the
      world and cannot be undone by re-running a stage.
- [x] **11.5** An agent may prepare, preflight, reach the gate and **stop**. It
      can never mint the token. Assert this in the selftest.
- [x] **11.6** Record every deploy in the ledger: target, version, account,
      approving person, timestamp, resulting artefact id.
- [x] **11.7** Use the scripted process runner in tests so the whole deploy path
      is exercised without credentials.

## Done-when

1. `appbox-deployer` runs fastlane, shorebird and Cloudflare Pages command
   shapes under a scripted runner, asserted exactly.
2. `vercel` is not offered.
3. Gate 3 refuses to pass without a confirmation naming all three of target,
   version and account — **prove the negative for each one individually**.
4. An automated run reaches gate 3 and halts, minting nothing.
5. The ledger records a full deploy attempt.
