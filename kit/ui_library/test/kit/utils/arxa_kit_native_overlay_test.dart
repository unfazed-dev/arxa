import 'dart:async';

import 'package:cupertino_native_better/cupertino_native_better.dart'
    show CNTabBarRouteObserver;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart' show GetSnackBar, SnackbarController;
import 'package:arxa_kit_ui_library/utils/arxa_kit_native_overlay.dart';

void main() {
  // These are plain `test()`s, but the depth counter now consults
  // `SchedulerBinding.instance` to decide whether it is safe to notify
  // synchronously (it defers when the change lands mid-build — see
  // `_ModalDepthNotifier` in the vendor's `tab_bar.dart`). Without a binding
  // that getter throws. Initializing it is what Flutter's own error text
  // prescribes, and it changes nothing these tests assert: outside a frame the
  // phase is `idle`, so notification stays synchronous exactly as before.
  TestWidgetsFlutterBinding.ensureInitialized();

  int depth() => CNTabBarRouteObserver.anyModalDepth.value;

  tearDown(() {
    // Drain any depth a test left behind so the static global can't leak
    // between tests. markAnyModalInactive clamps at zero.
    while (depth() > 0) {
      CNTabBarRouteObserver.markAnyModalInactive();
    }
  });

  test(
      'kit.ui-library.native-overlay — balances depth for a plain future that completes on dismiss',
      () async {
    expect(depth(), 0);
    await arxaKitWithNativeChromeHidden(() async {});
    expect(depth(), 0);
  });

  test(
      'kit.ui-library.native-overlay — balances depth when present() returns null',
      () async {
    await arxaKitWithNativeChromeHidden(() => null);
    expect(depth(), 0);
  });

  test('kit.ui-library.native-overlay — balances depth when present() throws',
      () async {
    await expectLater(
      arxaKitWithNativeChromeHidden(() => Future.error(StateError('boom'))),
      throwsStateError,
    );
    expect(depth(), 0);
  });

  test(
      'kit.ui-library.native-overlay — HOLDS the hide while a SnackbarController is live '
      '(showCustomSnackBar resolves at show time, not dismiss)', () async {
    // Regression for the iOS blur bleed-through: stacked_services'
    // showCustomSnackBar completes one frame after the snackbar APPEARS,
    // resolving to GetX's SnackbarController. The helper must keep
    // anyModalDepth > 0 until controller.future (dismissal) completes.
    final controller = SnackbarController(const GetSnackBar(message: 'x'));
    unawaited(arxaKitWithNativeChromeHidden(() async => controller));

    // Let present() resolve and the helper reach the controller await.
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(depth(), 1,
        reason: 'hide must stay active while the snackbar is on screen — '
            'releasing here is the sharp-native-views-over-blur bug');
    // controller.future can only complete via a real show/dismiss cycle;
    // tearDown drains the held depth.
  });

  // ADR 0010 second amendment: native glass scrim lease. On the test host
  // LiquidGlassContainer degrades to its bare child, so these exercise the
  // lease/refcount/fade machinery, not the UIKit effect itself.
  Finder scrimDim() => find
      .byWidgetPredicate((w) => w is ColoredBox && w.color == Colors.black54);

  /// The scrim's own AnimatedOpacity target — located through the dim so a
  /// stray AnimatedOpacity elsewhere in the overlay can't satisfy the finder.
  double scrimOpacity(WidgetTester tester) => tester
      .widget<AnimatedOpacity>(
          find.ancestor(of: scrimDim(), matching: find.byType(AnimatedOpacity)))
      .opacity;

  /// The value actually on screen — AnimatedOpacity's internal FadeTransition
  /// animation, not the widget's target. Pins the tween itself: a swap to
  /// plain `Opacity` breaks the finder, and `duration: Duration.zero` can't
  /// produce a mid-tween fractional value.
  double renderedScrimOpacity(WidgetTester tester) => tester
      .widget<FadeTransition>(
          find.ancestor(of: scrimDim(), matching: find.byType(FadeTransition)))
      .opacity
      .value;

  testWidgets(
      'kit.ui-library.native-overlay — scrim lease mounts one shared entry, '
      'ref-counts, and removes after fade', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    final overlay = tester.state<OverlayState>(find.byType(Overlay).first);

    final leaseA = ArxaKitSnackbarScrimLease.acquire(overlay, Colors.black54);
    final leaseB = ArxaKitSnackbarScrimLease.acquire(overlay, Colors.black54);
    await tester.pump();

    expect(ArxaKitSnackbarScrimLease.debugScrimMounted, isTrue);
    expect(ArxaKitSnackbarScrimLease.debugDepth, 2);
    expect(scrimDim(), findsOneWidget,
        reason: 'two concurrent leases share ONE entry — no double dim');

    unawaited(leaseB.release());
    await tester.pump(const Duration(milliseconds: 250));
    expect(ArxaKitSnackbarScrimLease.debugScrimMounted, isTrue,
        reason: 'outstanding lease must keep the scrim up');

    unawaited(leaseA.release());
    await tester.pump(); // fade-out begins
    await tester.pump(const Duration(milliseconds: 250)); // fade elapses
    await tester.pump(); // removal lands
    expect(ArxaKitSnackbarScrimLease.debugScrimMounted, isFalse);
    expect(scrimDim(), findsNothing);
  });

  testWidgets(
      'kit.ui-library.native-overlay — helper inserts scrim for lifetime of '
      'present() and tears it down after', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    final overlay = tester.state<OverlayState>(find.byType(Overlay).first);

    final presented = Completer<void>();
    final done = arxaKitWithNativeChromeHidden(
      () => presented.future,
      scrimOverlay: overlay,
    );
    await tester.pump();

    expect(scrimDim(), findsOneWidget,
        reason: 'scrim must be up while the presentation is live');
    expect(depth(), 1, reason: 'chrome hide and scrim travel together');

    presented.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump();
    await done;

    expect(scrimDim(), findsNothing);
    expect(ArxaKitSnackbarScrimLease.debugScrimMounted, isFalse);
    expect(depth(), 0);
  });

  testWidgets(
      'kit.ui-library.native-overlay — scrim FADES IN: mounts at opacity 0 and '
      'lights on the next frame', (tester) async {
    // Regression: `acquire` used to set `_visible` true BEFORE inserting the
    // entry, so AnimatedOpacity's first build was already 1.0 and never
    // animated — a full-screen Glass.regular frost SNAPPED on while dismissal
    // got a 200ms fade. Symmetry is the assertion: 0 on the mount frame, 1
    // after the post-frame callback lands.
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    final overlay = tester.state<OverlayState>(find.byType(Overlay).first);

    final lease = ArxaKitSnackbarScrimLease.acquire(overlay, Colors.black54);
    await tester.pump(); // mount frame

    expect(scrimOpacity(tester), 0.0,
        reason: 'the frost must not snap on at full strength');

    await tester.pump(); // post-frame callback lights it
    expect(scrimOpacity(tester), 1.0,
        reason: 'the fade-in target must be reached once mounted');

    // Pin the tween, not just the target: halfway through the 200ms fade the
    // RENDERED opacity must be strictly mid-flight. Duration.zero or a plain
    // `Opacity` swap would pass the target assertions above yet fail here.
    await tester.pump(const Duration(milliseconds: 100));
    final midFade = renderedScrimOpacity(tester);
    expect(midFade, greaterThan(0.0),
        reason: 'mid-tween the scrim must already be visible');
    expect(midFade, lessThan(1.0),
        reason: 'mid-tween the scrim must not have snapped to full strength — '
            'a zero-duration tween would already read 1.0 here');

    await tester.pump(const Duration(milliseconds: 250));
    unawaited(lease.release());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump();
    expect(ArxaKitSnackbarScrimLease.debugScrimMounted, isFalse);
  });

  testWidgets(
      'kit.ui-library.native-overlay — a second lease in the SAME turn cannot '
      'defeat the fade-in', (tester) async {
    // GetX queues concurrent snackbars, so two acquires can land in one
    // synchronous turn: the first creates the entry dark and schedules the
    // post-frame, the second finds `_entry != null`. If that second call
    // flipped `_visible` immediately it would light the entry BEFORE its mount
    // frame rendered and the frost would snap on exactly as before the fix —
    // the concurrent path being the one GetX actually produces.
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    final overlay = tester.state<OverlayState>(find.byType(Overlay).first);

    final leaseA = ArxaKitSnackbarScrimLease.acquire(overlay, Colors.black54);
    final leaseB = ArxaKitSnackbarScrimLease.acquire(overlay, Colors.black54);
    await tester.pump(); // mount frame

    expect(scrimOpacity(tester), 0.0,
        reason: 'the co-arriving lease must not pre-light the mount frame');

    await tester.pump();
    expect(scrimOpacity(tester), 1.0);

    unawaited(leaseA.release());
    unawaited(leaseB.release());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump();
    expect(ArxaKitSnackbarScrimLease.debugScrimMounted, isFalse);
  });

  testWidgets(
      'kit.ui-library.native-overlay — scrim survives a new lease arriving '
      'mid-fade', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    final overlay = tester.state<OverlayState>(find.byType(Overlay).first);

    final leaseA = ArxaKitSnackbarScrimLease.acquire(overlay, Colors.black54);
    await tester.pump();
    unawaited(leaseA.release());
    await tester.pump(const Duration(milliseconds: 100)); // mid-fade

    final leaseB = ArxaKitSnackbarScrimLease.acquire(overlay, Colors.black54);
    await tester.pump(const Duration(milliseconds: 250));
    expect(ArxaKitSnackbarScrimLease.debugScrimMounted, isTrue,
        reason: 'the mid-fade re-lease must cancel the pending removal');

    unawaited(leaseB.release());
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump();
    expect(ArxaKitSnackbarScrimLease.debugScrimMounted, isFalse);
  });
}
