# 14 — Dogfood and smoke test

**Goal.** app_box designs and builds **itself** — proving the designer on a
desktop *and* a mobile design, and the pipeline end to end.

**Depends on:** 01, 05, 06, 07, 08. **This is the acceptance test for the
whole product.**

## The two designs (both are shipping work, neither is throwaway)

| # | design | targets | viewports exercised |
|---|---|---|---|
| **D1** | app_box's own macOS desktop app | `macos` | desktop only → **3 layout files** |
| **D2** | the iOS companion | `ios` | mobile + tablet → **4 layout files** |

Together they prove the derivation table end to end: one target implying one
viewport, another implying two, and the form-factor emission following each.

## Phase A — design (founder-led, starts the moment plan 01 lands)

- [ ] **14.1** Run `app-box-designer` against
      [`../../design/brief.md`](../../design/brief.md) to produce **D1**: 14
      surfaces, states per the brief, authored at the desktop width.
- [ ] **14.2** Author `registry.json` and a `surfaceId` in every viewmodel while
      designing — **never back-filled**.
- [ ] **14.3** Iterate on D1 freely. This is the founder's fine-tuning window
      and runs in parallel with plans 02–13.
- [ ] **14.4** Produce **D2**, the companion, at mobile and tablet widths.

## Phase B — freeze

- [ ] **14.5** Freeze D1. Expect the six inputs plus a `structure.json`
      generated from the authored registry — **not** filename-inferred.
- [ ] **14.6** Confirm the freeze renders D1 at **one** width and D2 at **two**,
      from targets alone.
- [ ] **14.7** Confirm no surface reports a console error, and that the error
      count is **exact** — the reporting bug that inflated counts ~4× is fixed
      in plan 04.

## Phase C — scaffold and review

- [x] **14.8** Scaffold D1. Expect **three** layout files per surface, not five.
      *(verified: scaffolder emits base + desktop + viewmodel = 3 for macos; the
      review gate's form_factor_files is now §16-derivation-aware and ENFORCES
      the 3-file set, rejecting the legacy 5-file demand — commit 31653b5.)*
- [ ] **14.9** Run every gate. Record the pass count.
      *(ran run_all on scaffolded D1 — recorded: intake ✓ freeze ✓ structure ✓
      coverage ✓ review ✓ (15/15 stubs) · scaffold N/A (app-root has no pubspec.yaml
      yet — the dogfood target must be a real Flutter project for the shell/chrome
      checks) · deploy FAIL (human gate 3: version/account unconfirmed). 5 PASS /
      1 N/A / 1 FAIL.)*
- [ ] **14.10** Scaffold D2. Expect **four** files per surface.

## Phase D — the smoke tests that matter

- [ ] **14.11** **Round-trip:** create a feature, delete it, regenerate — the
      tree is byte-identical.
- [ ] **14.12** **Orphan:** delete a registry entry without the fixer — coverage
      fails and names the orphaned directory.
- [ ] **14.13** **Drift:** hand-edit `structure.json` by one character —
      structure fails. Add a surface file undeclared in the registry — structure
      fails (porcelain, not `git diff`).
- [ ] **14.14** **Targets:** add `web` to D1's targets — the design approval goes
      stale, loudly, because the frozen input no longer covers the deliverable.
- [ ] **14.15** **Gates:** an automated run reaches each of the three human
      gates and halts, minting nothing.
- [ ] **14.16** **Credentials:** write → restart → read back **in a signed,
      notarised build**.
- [ ] **14.17** **Prototype runtime:** serve D1 with **no Node on `PATH`**.
- [ ] **14.18** **Companion:** pair, serve, kill the server, confirm the FAB
      goes dead while the WebView still shows the last render.
- [ ] **14.19** **Michelle's path:** on a clean machine with no app_box context,
      install → showcase app launches by itself → reach a working prototype
      without reading any documentation. **Time it.** If it exceeds twenty
      minutes, that is a finding, not a pass.

## Done-when

1. D1 and D2 both pass every gate.
2. Form-factor counts differ correctly between them (3 vs 4) — derived, never
   configured per surface.
3. All smoke tests in Phase D pass, **including every negative case**.
4. app_box's macOS app, built by app_box, runs and can drive its own pipeline.
5. A written report records: gate pass counts, the Michelle timing, and every
   place a human had to intervene that the plans did not predict.

## The honest bar

If any gate passes while something is broken, **that is the failure**, not the
broken thing. This project's recurring defect is green gates over real defects:
a hash keyed on mtime, a self-test asserting the defective value, an asset check
that verified strings instead of resolving paths, a drift check guarded on a
file the producer does not have. Every one was green.
