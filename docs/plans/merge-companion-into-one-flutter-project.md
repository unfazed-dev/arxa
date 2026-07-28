# Merge `companion/` into `app/` — one Flutter project, two runners

**Status:** recommended, **not started**. Blocked on plan 14 Phase A (D2).
**Raised by:** the founder — *"why do we need 2 separate apps when they can both
be developed under one stacked flutter app — that is the point of flutter"*.

## Verdict

**The instinct is right and the objection is not a matter of taste.** Two
Flutter projects that ship to two Apple platforms from one company, sharing a
config pattern, a channel protocol and a design language, is the shape Flutter
exists to collapse. What follows is the evidence that it is *mechanically* easy,
and the reason it should still not be done this week.

## Why the merge is clean

Measured, not assumed:

| | `app/` | `companion/` |
|---|---|---|
| package | `app_box` | `app_box_companion` |
| platform folders | **`macos/` only** | **`ios/` only** |
| architecture | Stacked MVVM + locator + generated router | plain `MaterialApp` + `StatefulWidget` |
| Dart files in `lib/` | ~90 | 16 |
| stacked deps | yes | **zero** |
| tests | 36 pass | 49 pass |

**There is no platform overlap at all.** A single Flutter project owning both
`macos/` and `ios/` runner folders over one `lib/` is the stock Flutter layout —
not a workaround. Nothing has to be reconciled, because nothing collides.

The dependency sets do not fight either. `webview_flutter` is used only on the
phone path and `flutter_secure_storage` only on the desktop path, but both
resolve fine in one `pubspec`; a plugin that goes unused on a platform costs a
few KB, not a conflict. The one genuine runtime asymmetry — the desktop shells
out to the pipeline via `dart:io Process`, which compiles on iOS and fails at
runtime — is a platform branch, exactly the kind Flutter apps write every day.

## Why it should not happen yet

Three reasons, in descending order of weight.

**1. The companion has no design to merge toward.** Plan 14 Phase A (14.1–14.4)
is entirely unticked. **D2 — the companion design at mobile and tablet widths —
does not exist.** Merging now means hand-authoring the phone UI a second time,
then throwing it away when D2 lands.

**2. Hand-merging repeats the defect being fixed.** Plan **12.1** — *"Scaffold
the companion through app_box's own pipeline… this is the mobile half of the
designer proof — do not hand-build it"* — is the one step in plan 12 still
unticked, and `companion/README.md` says plainly: *"this run hand-built the
minimal surface."* That is why the companion is not a Stacked app: it never went
through the generator. Merging it by hand is the same violation at ten times the
size, and it would quietly convert a known, documented shortcut into permanent
architecture.

**3. The prototype is not validated.** The founder's own note — *"i have not
even finished prototyping to validate the smoke test dog food"* — is the
governing constraint. Restructuring the two deliverables the dogfood is supposed
to *produce*, before the dogfood has run, pours concrete while the ground moves.

## What "done" looks like

When D2 exists, the merge is roughly a day, in this order:

1. **`flutter create --platforms=ios .`** inside `app/`. Verify the iOS runner
   builds *before* moving a single file.
   **Expect one known warning here:** `flutter_js` (hosted) has not adopted
   Swift Package Manager, so the first iOS build warns about it just as macOS
   does today. It builds via the CocoaPods fallback, and `gates/native_deps`
   tracks the debt. iOS is the harder migration — its plugin is Objective-C,
   needing `ios/flutter_js/Sources/flutter_js/include/flutter_js/` with the
   public headers moved; the recipe is in `gates/native_deps/README.md`.
2. **Port the iOS ceremony** from `companion/ios/Runner/Info.plist` —
   `NSLocalNetworkUsageDescription`, `NSBonjourServices` (`_appbox._tcp`),
   `NSCameraUsageDescription`. Without these, discovery dies with
   `NSNetServicesErrorCode: -72008` (plan 12.2).
3. **Move the platform-agnostic half first** — `companion/lib/{pairing,channel,
   prototype,pipeline}/` into `app/lib/`, with their 49 tests. This is pure Dart
   with no UI and no platform calls; it should go green immediately and is the
   part that carries the security properties (cert pin, nonce lifecycle,
   approval provenance). **Do not let this land without its tests.**
4. **Merge the config files.** `companion.config.json` and `app_box.config.json`
   become one bundled config with a `companion` section — R3 forbids literals in
   code, and two config files for one app reintroduces drift.
5. **Generate the phone surfaces from D2 through the pipeline** — this is plan
   12.1, finally done properly, and it is what makes the merge worth doing.
6. **Branch the initial route by platform**, not by build flavour: one app that
   presents the builder on macOS and the remote control on iOS.
7. **Delete `companion/`** in the same commit that proves the iOS build from
   `app/`, so the tree never carries two answers at once.

### What must not be lost in the move

The companion's value is not its UI, it is six security properties with tests
behind them. Any merge that breaks one of these is a regression regardless of
what it makes prettier:

- the fingerprint **pin** (a relayed QR must fail),
- the **no-relay** rule — its absence is the security property, not a missing
  feature,
- the nonce lifecycle,
- **an agent can never mint an approval** — only a paired device's human can,
- revoking a device drops the session immediately,
- the FAB reads the **channel**, never the WebView, so a dead server cannot look
  alive behind a stale render.

## The cost of waiting

Low, and it shrinks. The duplication today is one `pubspec`, one `analysis_options`
and one config loader — perhaps 40 lines. Nothing in `companion/lib/` is
Stacked-shaped yet, so nothing has to be un-picked later. The longer path is not
more expensive; it is the same work, done once, from a design.
