# Inspect kits — the honesty layer

Actor: Evan (founder, settings mode) · Shell: settings-shell · Surfaces:
`settings.kits` → `stage_shell_settings_kits_view` (wired vs **stubbed**) ·
Decision refs: architecture.md §17 (kit consumption — vendor at pinned SHA;
the advertise rule), `stub-inventory.md` (5 of 23 kits partial; Stripe/PayPal/
auth/map/Vercel throw `UnimplementedError`), `stub-remediation.md` (three test
tiers — advertise at the tier passed)

## Trigger

Evan opens the settings tab to see what is genuinely wired. Or: a pre-build
readiness pass — before the 💳 builder phase, Evan (or the pipeline) consults
this surface to confirm which capabilities are real. Not a gate; a read.

## Entry / exit

- Entry criteria: the kit registry is loaded; the per-provider `verification`
  field is populated (stub-remediation.md step 1 — until it lands, status is
  read from the exception message, which is the *“wired is a grep”* smell this
  surface exists to kill).
- Exit states: **reviewed** — Evan has seen wired-vs-stubbed for every kit and
  knows which capabilities he can build against · **flagged** — Evan notes a
  stubbed provider he needed and routes to settings (BYO key) or defers the
  feature. No state is written; this surface never mutates the pipeline.

## Happy path

1. `settings.kits` renders the full registry: **23 kits**, one row each. Status
   is read from the registry's `verification` field — `stub | port-tested |
   sim-verified | device-verified` — never inferred from whether a call happens
   to succeed (stub-remediation.md).
2. Each row shows the kit's phase and, per provider, its honest status. The 5
   partial kits surface their throwing providers explicitly:
   **payments** — Stripe `STUBBED — throws`, PayPal `STUBBED — throws`, Apple
   Pay wired · **auth** — Apple sign-in `STUBBED — throws`, Google sign-in
   `STUBBED — throws`, `SeedAuthBackend` stub (phase-4) · **maps** — OSM
   `STUBBED — throws`, Mapbox `STUBBED — throws` · **deploy** — fastlane /
   shorebird / CF Pages wired, **Vercel `STUBBED — throws`**. A kit can be
   phase `stable` overall and still throw for one provider (Vercel) — the
   per-provider status is the truth, not the phase label.
3. Evan filters or searches: *“show stubbed only”*, *“payments”*, *“tier ≥
   sim-verified”*. The filter is a view control, not a pipeline decision.
4. Evan reads the tier each wired provider has reached. The three tiers
   (stub-remediation.md) define what *wired* actually means:
   **Tier 1 — port + scripted fake** (no toolchain, runs in CI; the
   `KitProcessRunner` / `ScriptedProcessRunner` pattern — *“do we call the SDK
   correctly and handle its failures?”*) · **Tier 2 — simulator/emulator** (UI,
   layout, flow wiring, seeded data; cannot prove entitlements or real tokens) ·
   **Tier 3 — physical device** (entitlements, certificates, real tokens;
   mandatory before `device-verified`, no shortcut).
5. No action needed — informational. Evan exits knowing which capabilities are
   real vs stubbed. (No gate steps: this surface asserts nothing and writes
   nothing.)

## Decision points

- **None — read-only informational.** The only branching is the view filter
  (all / stubbed-only / by-tier), which changes what is rendered, not what is
  true. The enforceable decision lives downstream in the **advertise-gate**: a
  provider may only be advertised at the tier it has passed
  (stub-remediation.md) — *“no provider may be advertised above its recorded
  tier.”* This surface is the human-readable projection of the same field that
  gate reads.

## Edge cases

- **A buyer picks Stripe and discovers `UnimplementedError` at build time.**
  This surface exists to prevent that — the stub must be visible *before*
  build, not discovered when a scaffolded screen calls it. *A buyer who meets
  an `UnimplementedError` the UI offered her has been misled*; that is her
  stated abandon condition (stub-remediation.md).
- **Kit freshness (vendored at pinned SHA).** §17: the vendored tooling is
  compared against upstream and **fails on divergence**, asserted with
  `git status --porcelain` semantics — not a hand-bumped version string. If the
  pinned SHA has drifted, the row renders stale and the freshness check is the
  thing to fix, not the label.
- **New kit added.** Status updates from the kit registry — the surface is a
  viewer, never the source. A newly registered kit appears at its declared
  `verification` tier; a kit no suite has run on defaults to `stub` and renders
  STUBBED until evidence promotes it.
- **Tier claimed by hand.** A provider's tier is set *only* by a suite that ran
  at that tier — Tier 3 cannot be claimed by a simulator run, and no tier may
  be set by editing the registry by hand (stub-remediation.md). A hand-edited
  tier is itself a red signal.
- **`verification` field absent.** Before stub-remediation.md step 1 lands,
  status lives in exception messages. The surface degrades to reading those —
  and must say so, rather than rendering a confident green it cannot prove.

## Screens

| Step | Surface / sheet / dialog |
|---|---|
| 1–4 | `stage_shell_settings_kits_view` — 23-kit list, per-provider status, tier badge, filter/search |
| 5 | same view — exit (no transition; informational) |

## Notes

- *“A buyer who picks Stripe and discovers `UnimplementedError` at build time
  has been misled.”* This surface is the honesty layer: it makes the
  advertise-gate's rule visible to the operator, so a stub is never offered
  without a STUBBED label.
- The 💳 licence precondition sits at `app-box-builder`
  (`../build-shell/run-build.md`, architecture.md §17) — builder is where
  payment lives *and* where a scaffolded screen first calls a kit. Inspecting
  kits beforehand is the readiness check that keeps build from turning red for
  a stub it should never have been offered.
- Michelle reads the same status through a legibility filter in
  `../../michelle-buyer/settings-shell/byo-key-setup.md` — she brings her own
  key to promote a stubbed provider toward wired.
- State is viewer-only: everything rendered comes from the kit registry's
  `verification` field and the vendored-SHA freshness check, never from paint
  or a probe at render time.
