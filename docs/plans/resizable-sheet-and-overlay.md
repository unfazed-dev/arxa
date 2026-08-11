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
