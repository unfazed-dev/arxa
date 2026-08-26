# Native detent-sheet fidelity (iOS)

## Problem

`arxaKitShowSheet` on iOS presents through `CNBottomSheet.showCupertino` →
`_CNDimmedSheetRoute extends CupertinoSheetRoute`: a **full-height** stacked-card
sheet. On device (clip 07-32-07) it reads as a flat, edge-to-edge dark page — no
rounded card, no system material, no grabber, no visible parent. The reference
(clip 07-36-12, the system share sheet — a real `UISheetPresentationController`)
shows the correct Apple presentation: partial-height rounded card, system
material, grabber, dimmed and visibly receding parent.

## External evidence (decides the mechanism)

- flutter/flutter **#169832**: `showCupertinoSheet` does not support detents;
  `CupertinoSheetRoute` is full-height only. The framework cannot produce the
  reference look today.
- A true native `UISheetPresentationController` cannot host arbitrary Flutter
  widget bodies from the same engine; a second engine (`FlutterEngineGroup`)
  runs a separate isolate — kit sheets carry app state, so that's out.
- Vendor Swift sources contain **no** sheet presentation code; all sheet
  machinery is Dart. The gating stack (`topModalRect`, `CNSheetGeometryProbe`,
  `markAnyModalActive`) already supports partial-height sheets.

Conclusion: keep the Flutter-drawn mechanism (do NOT kill it — it is the only
one that can host kit bodies) and fix its **presentation model** to reproduce
`UISheetPresentationController` detents faithfully.

## Plan

1. **New detent route** in vendor `bottom_sheet.dart`
   (`_CNDetentSheetRoute<T>`, PopupRoute):
   - Detents: `medium` (~0.5 of screen height) and `large`
     (full minus top gap). Default open at medium; `heightFactor` maps to a
     custom detent fraction.
   - Chrome: top-corner `ClipRSuperellipse` with the iOS sheet radius,
     system-material background (BackdropFilter blur + dynamic
     elevated-background color, dark-mode aware), centered grabber capsule.
   - Gestures: drag between detents with snap; fling/drag down past medium
     dismisses when `enableDrag`.
   - Barrier: dim behind every detent (matches UIKit default).
   - Large detent: drive parent recede (scale + corner radius on the
     presenting page) from the route's animation — same visual as
     `CupertinoSheetRoute`'s stack effect.
   - Reuse `CNSheetGeometryProbe` so `topModalRect` publishes the true card
     rect and native widgets under the sheet gate correctly.
2. **Wire `CNBottomSheet.showCupertino`** to the detent route (params:
   `detents`, keep existing surface); `arxaKitShowSheet` iOS branch defaults
   to medium-detent presentation.
3. **Verify**: build to device, re-record, compare against reference frames
   (card top edge, corners, grabber, material, dim) before declaring done.

## Trail

- consult-mode advisor call attempted; `status:"error"` (no API key on this
  machine) — proceeding on primary sources per advisor-conventions fallback.
