# Resizable sheet + native overlay

Follow-on to `sheet-and-theme-propagation-fixes.md`, which left one open item:
the iOS sheet was 92% of the screen with no way to change it, and no dim behind
it.

## What was asked

Showcase overlays card: three centered buttons opening the sheet at **92%
(current default) / 56% / 30%**, a **native slider inside the open sheet**
adjusting it live from **20% to 92%**, and the **native overlay visible**.

## The constraint that shapes the design

`CupertinoSheetRoute._topGap` is `final`, read once at construction
(`cupertino/sheet.dart:686,689`). **A live route cannot change its own height.**
`topGap` is therefore only usable for a height fixed at present-time.

Since the slider must resize the sheet *while it is open*, height cannot come
from `topGap` at all. It has to be owned by the sheet **body**, inside a route
left at its default size. That is the trade the user picked explicitly: the body
then draws its own top corners and grabber, because the route's own chrome sits
at the route's top edge (92%), not the body's.

One mechanism, not two: the three buttons and the slider both drive the same
body-owned height. The buttons seed it, the slider moves it.

### Why the body can't just paint a transparent background

The obvious shortcut — pass `backgroundColor: Colors.transparent` and let the
showcase lay out whatever it wants — fails. `_RenderColoredBox` is constructed
with `HitTestBehavior.opaque` **unconditionally**, alpha 0 included
(`widgets/basic.dart:8528-8532`). A transparent `ColoredBox` over the dead space
above the sheet still swallows every tap, so the dim overlay would be visible but
inert. The kit must supply the bottom-anchored path so that space is occupied by
an `Align`, which does not hit-test where it has no child.

## Kit changes — `appBoxKitShowSheet`

Two new parameters, both additive; omitting them reproduces today's behaviour.

### `ValueListenable<double>? heightFactor`

Fraction of screen height. `null` (default) = framework owns the height, exactly
as now. Non-null routes both tiers through a bottom-anchored, listener-driven
body so a value change resizes the live sheet.

- **iOS** — route keeps the framework default `topGap` and sets
  `showDragHandle: false`; the body is
  `Align(bottomCenter, ValueListenableBuilder(→ SizedBox(height: f × H)))`
  wrapped in `ClipRSuperellipse` with top-only r=12 (matching the route's own
  clip) over `AppBoxKitFrostedSurface(borderRadius: 0)`, plus a kit-drawn 36×5
  grabber using the framework's own constants (`sheet.dart:704-708`).
- **Android** — `isScrollControlled: true` and the same
  `ValueListenableBuilder` sizing. Material's sheet sizes to its child, so a
  per-frame child height change *is* the resize. Its own drag handle is
  unaffected.

### `bool showOverlay = true`

- **iOS** — needs a subclass, because `CupertinoSheetRoute.barrierColor` is
  hardcoded to transparent and `barrierDismissible` to false
  (`sheet.dart:777,780`). Both are plain `@override` getters on a class with no
  `final`/`base`/`sealed` modifier (`:634`), so a ~10-line subclass in the vendor
  re-overrides them: `kCupertinoModalBarrierColor` (`0x33000000` light /
  `0x7A000000` dark — the SDK's own modal barrier) and `barrierDismissible` tied
  to `enableDrag`. `barrierLabel` must become non-null; `ModalRoute` dereferences
  it when the barrier is dismissible.
- **Android** — already dims; `showOverlay: false` maps to a transparent
  `barrierColor`.

**Defaulting this to `true` is a deliberate behaviour change across every kit
sheet.** Justification: `UISheetPresentationController` dims behind *every*
detent unless `largestUndimmedDetentIdentifier` says otherwise, so no-dim was the
deviation. It also restores the honest meaning of `isDismissible` on iOS — the
previous pass had to document that it could only map to `enableDrag`, because the
route offered no tappable barrier to map it onto.

### Known test fallout

`appbox_kit_native_sheet_test.dart` currently asserts that an outside tap does
**not** dismiss the iOS sheet. That assertion encodes the old no-barrier
behaviour and must be inverted, not deleted — the sheet should now dismiss.

## Showcase changes — overlays card

`ShowcaseComponentsOverlaysCardWidget` becomes stateful to own a
`ValueNotifier<double>`, disposed with the State.

- A centered `Row` of three equal-width buttons — `92%`, `56%`, `30%` — each
  seeding the notifier and presenting.
- The sheet body carries `AppBoxKitNativeSlider(min: 0.20, max: 0.92)` bound to
  that same notifier, so dragging resizes the sheet under the finger.

## Verification

Kit tests: height honoured per tier, a notifier change resizes a live sheet,
overlay present by default and suppressible, and a tap above a short sheet
reaches the barrier and dismisses. Showcase test: the three buttons present and
each opening at its height.

## Shipped — 2026-08-11 (`869ddd5`)

ui_library 303 tests (+6), vendor 121, showcase 120; `flutter analyze` clean in
all three.

### Measured, not assumed

A throwaway probe answered the two questions the design rested on before any
production code was written:

- The route's content box is **552 of 600 = 0.9200** exactly — `(1 - 0.08) × H`,
  confirming the default height and giving the clamp its ceiling.
- A tap at 10% from the top of a 30%-tall bottom-anchored sheet **dismissed it**.
  Neither the `Align` nor the transition mixin's drag recognizer swallows the
  gap, so the overlay is genuinely live. Had this failed, the whole approach
  would have needed a different filler for that space.

### A test that was passing for the wrong reason

The pre-existing "an outside tap does NOT dismiss" case tapped `Offset(400, 50)`
on an 800×600 surface while the route's box begins at `0.08 × 600 = 48`. It was
tapping two pixels *inside* the sheet, so it would have passed with or without a
barrier — it never tested the thing it was named for. It is now inverted and taps
`y=20`, in the strip that is actually uncovered.

### Mutation-checked

Each new assertion was proven load-bearing by breaking the code it covers:

| Mutation | Result |
|---|---|
| `barrierColor` forced to null | 3 failures |
| `heightFactor` ignored on the iOS tier | 3 failures |
| gap filled with a transparent `ColoredBox` instead of `Align` | 1 failure — exactly `the space above a short sheet reaches the overlay` |

The third is the interesting one: it is the only evidence that the
`HitTestBehavior.opaque` detail is real rather than a plausible-sounding reading
of the SDK, and it fails precisely the one test that would notice.

### Two bugs the first round shipped, found in review

Both were invisible to the six tests written alongside the feature, which is the
point worth keeping.

**1. The geometry probe measured the wrong box.** `CNBottomSheet.showCupertino`
wraps whatever `pageBuilder` returns in a `CNSheetGeometryProbe`. In the sized
path that output is the `Align`, which fills the route — so the published
`topModalRect` was **552 tall, not 180**, measured. Every `ModalHideMixin` widget
on the host page would have been told it was covered while 62% of the screen was
clear, tearing down native chrome for nothing — the same symptom class this whole
session started from.

Fixed by adding `injectGeometryProbe` to `showCupertino` and having the sized
body place the probe on the box that carries the height. Deliberately *not* by
adding a second probe: two publish into one `ValueNotifier` every frame,
last-writer-wins, and the dispose guard compares the rect to its own last value
so it cannot tell whose it is clearing.

**2. The sized sheet was not full width.** `Align` passes loose constraints, so a
`SizedBox` given only a height collapsed to its content's intrinsic width —
measured at 626 of 800, a centered floating card. That is exactly the shape the
Cupertino route was adopted to eliminate, reintroduced one layer down. Fixed with
`width: double.infinity`.

Only the relocated probe made either visible. The height assertion passed
throughout.

### A mutation that passed, and what it changed

Forcing `injectGeometryProbe: true` initially left all 18 tests green. Two probes
were running, and the rect still came out right because the inner one happened to
fire second — a correct value produced by ordering luck. A correct rect is
therefore not evidence that only one probe exists, so the invariant now has its
own assertion (`findsOneWidget` on the probe) rather than being inferred from the
rect. With that in place the mutation fails as it should.

### Pre-existing sheets are now barrier-dismissible — checked, not assumed

`showOverlay` defaulting to true makes every existing kit sheet dismissible by an
outside tap, since `barrierDismissible => enableDrag` and `enableDrag:
isDismissible`, which defaults true. That is a restoration rather than a break:

- `AppBoxKitBottomSheetService` already forwards a parameter *named*
  `barrierDismissible` into `isDismissible` (`:56`, `:133`) — callers were
  already declaring this intent, and iOS was silently ignoring it.
- `AppBoxKitNotificationService.notice` documents itself as "Fire-and-forget:
  dismissible by drag/barrier" (`:209-210`). iOS was violating its own doc.
- The ask surfaces' Cancel button already pops with no value
  (`appbox_kit_ask_surfaces.dart:79,135`), so a dismissal yields the same `null`
  callers already had to handle. No new ambiguity is introduced.

### Known limitation

On the Android tier the Material drag handle is laid out above the sized child
rather than inside it, so a presented sheet is the handle's height taller than
[heightFactor] asks. Not corrected: the handle's height is a private Material
constant, and subtracting a guess at it would drift the moment the theme changes
it. The iOS tier is exact.
