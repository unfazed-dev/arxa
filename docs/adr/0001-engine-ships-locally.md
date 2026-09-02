---
status: accepted
date: 2026-09-02
---

# The engine ships on the customer's machine; it is never hosted

arxa is a solo-operated, BYO-LLM-key, flat-licence tool whose paying persona is agencies who
must scaffold offline and during any arxa outage. We ship the compiled engine (13 MB Dart AOT)
as a Tauri sidecar next to the harness, gate it with an offline-verified Ed25519 entitlement
token with a 30-day offline window, and deliver kits from a static signed bucket — the
Unity/JetBrains shape, not the Cursor/FlutterFlow hosted shape. Hosting was rejected because it
turns one founder into an on-call SRE, bricks paid scaffolds whenever the server or the company
blinks, copies the competitor we position against, and protects almost nothing: the value is in
kits, harness workflow and updates, not in a patchable 13 MB binary.

## Considered options

- **A. Local sidecar** — chosen.
- **B. Local engine + static signed kit bucket** — chosen alongside A (kits are not compiled in).
- **C. Local engine + optional hosted conveniences** (kit CDN, resold cloud builds, later Totem
  Cloud) — reserved as the growth path; never between the user and a scaffold.
- **D. Hosted engine** — rejected (reasons above).

## Consequences

- An offline token with grace accepts some licence sharing. We choose revenue leakage over
  support burden and outage liability.
- The engine currently resolves kits from a repo checkout (`findRepoRoot()`); kit distribution
  and the Linux build are open work items, not hosting arguments.

## Revisit only if one of these fires

1. Verified pirated paid seats exceed 10 % of paid seats in a quarter.
2. A planned feature cannot run on a developer laptop (non-BYO model, >8 GB working set, GPU).
3. A contract demands revocation faster than the token TTL and refuses a shorter TTL.
4. A second full-time operator exists to carry on-call.

Full analysis: `docs/research/payment-architecture/engine-distribution-options.md`.
Decision log: arxa-studio D98.
