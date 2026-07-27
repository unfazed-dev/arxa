# 06 — Targets drive widths and emission

**Goal.** One value — `targets` — derives freeze widths, form-factor emission
and platform ceremonies. Nothing about platforms is hardcoded anywhere.

**Blocks:** 14. **Depends on:** 04. **Runs parallel to 05 and 07.**

## The rule (§11, §16)

`--targets` is **platform-only**. Viewports **derive**. `--desktop-macos` fuses
two independent axes and is rejected: macOS is a platform, desktop is a
viewport; an iPad is iOS at tablet width.

| target | viewports implied | ceremonies |
|---|---|---|
| `ios` | mobile, tablet | `NSLocalNetworkUsageDescription`, `NSBonjourServices` |
| `android` | mobile, tablet | adaptive icons, splash |
| `web` | mobile, tablet, desktop | `index.html`, renderer choice |
| `pwa` | inherits web | `manifest.json`, service worker, offline shell |
| `macos` `linux` `windows` | desktop | platform dir, window min size, **Keychain Sharing entitlements in both `DebugProfile` and `Release`** |

Viewport set is the **union**; mobile always present.

## Steps

- [x] **6.1** Put the derivation table in `pipeline/state/` as **data**, not
      code — a config-driven map, so adding a target is a data edit (R3).
- [x] **6.2** `targets` are written to **state**, never carried as a flag.
      Three surfaces will set them (GUI, CLI, companion); as a flag they drift
      and a design frozen for two viewports gets scaffolded for three.
- [x] **6.3** **But gate and golden runs take targets explicitly.** The
      upstream config this pattern came from is deliberate: *"Neither script
      auto-loads config; pass `--config` explicitly (so deterministic snapshot
      runs stay flag-free → golden stable)."* Ambient state in a reproducibility
      run is precisely the stale-green defect documented in the research.
- [x] **6.4** `gates/freeze/` renders each surface at **every width in the
      derived set**, reading widths from config. Remove the 390×844 literals
      (two in the freeze script, one in the emitter).
- [x] **6.5** `gates/coverage/` requires **exactly the derived form-factor set**.
      Replace the unconditional five-file list. `--targets macos` ⇒
      `_view.dart`, `_view.desktop.dart`, `_viewmodel.dart` — **three files**.
- [x] **6.6** **Do not** emit empty `.mobile`/`.tablet` files to satisfy a
      counter. A file that exists, passes the check and is never rendered is the
      stale-green pattern in its purest form (§16).
- [x] **6.7** Hash `targets` into the design-approval invalidation. Adding a
      target after approval means the frozen input no longer covers the
      deliverable — the approval must go stale, loudly.
- [x] **6.8** Platform ceremonies fire from targets. At minimum implement the
      three confirmed instances: iOS local-network keys, macOS Keychain Sharing
      entitlements **in both entitlement files**, and PWA manifest + service
      worker.

## Done-when

1. `--targets macos` → freeze renders **one** width; coverage requires **three**
   files; a fourth file present is not required and its absence is not a
   failure.
2. `--targets ios,android` → freeze renders **two** widths; coverage requires
   four files (view, mobile, tablet, viewmodel).
3. `--targets ios,android,web` → **three** widths.
4. `grep -rn '390\|744\|1280' gates/ tools/ pipeline/` finds **no literals** —
   all reads come from config.
5. Changing `targets` after approval invalidates the approval token.
6. Each ceremony's absence fails its gate, naming the missing file.
