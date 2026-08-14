import 'dart:async';

import 'package:cupertino_native_better/cupertino_native_better.dart'
    show CNTabBarRouteObserver;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart' show GetSnackBar, SnackbarController;
import 'package:appbox_kit_ui_library/utils/appbox_kit_native_overlay.dart';

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

  test('kit.ui-library.native-overlay — balances depth for a plain future that completes on dismiss',
      () async {
    expect(depth(), 0);
    await appBoxKitWithNativeChromeHidden(() async {});
    expect(depth(), 0);
  });

  test('kit.ui-library.native-overlay — balances depth when present() returns null', () async {
    await appBoxKitWithNativeChromeHidden(() => null);
    expect(depth(), 0);
  });

  test('kit.ui-library.native-overlay — balances depth when present() throws', () async {
    await expectLater(
      appBoxKitWithNativeChromeHidden(() => Future.error(StateError('boom'))),
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
    unawaited(appBoxKitWithNativeChromeHidden(() async => controller));

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
  Finder scrimDim() => find.byWidgetPredicate(
      (w) => w is ColoredBox && w.color == Colors.black54);

  testWidgets(
      'kit.ui-library.native-overlay — scrim lease mounts one shared entry, '
      'ref-counts, and removes after fade', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    final overlay = tester.state<OverlayState>(find.byType(Overlay).first);

    final leaseA =
        AppBoxKitSnackbarScrimLease.acquire(overlay, Colors.black54);
    final leaseB =
        AppBoxKitSnackbarScrimLease.acquire(overlay, Colors.black54);
    await tester.pump();

    expect(AppBoxKitSnackbarScrimLease.debugScrimMounted, isTrue);
    expect(AppBoxKitSnackbarScrimLease.debugDepth, 2);
    expect(scrimDim(), findsOneWidget,
        reason: 'two concurrent leases share ONE entry — no double dim');

    unawaited(leaseB.release());
    await tester.pump(const Duration(milliseconds: 250));
    expect(AppBoxKitSnackbarScrimLease.debugScrimMounted, isTrue,
        reason: 'outstanding lease must keep the scrim up');

    unawaited(leaseA.release());
    await tester.pump(); // fade-out begins
    await tester.pump(const Duration(milliseconds: 250)); // fade elapses
    await tester.pump(); // removal lands
    expect(AppBoxKitSnackbarScrimLease.debugScrimMounted, isFalse);
    expect(scrimDim(), findsNothing);
  });

  testWidgets(
      'kit.ui-library.native-overlay — helper inserts scrim for lifetime of '
      'present() and tears it down after', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    final overlay = tester.state<OverlayState>(find.byType(Overlay).first);

    final presented = Completer<void>();
    final done = appBoxKitWithNativeChromeHidden(
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
    expect(AppBoxKitSnackbarScrimLease.debugScrimMounted, isFalse);
    expect(depth(), 0);
  });

  testWidgets(
      'kit.ui-library.native-overlay — scrim survives a new lease arriving '
      'mid-fade', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    final overlay = tester.state<OverlayState>(find.byType(Overlay).first);

    final leaseA =
        AppBoxKitSnackbarScrimLease.acquire(overlay, Colors.black54);
    await tester.pump();
    unawaited(leaseA.release());
    await tester.pump(const Duration(milliseconds: 100)); // mid-fade

    final leaseB =
        AppBoxKitSnackbarScrimLease.acquire(overlay, Colors.black54);
    await tester.pump(const Duration(milliseconds: 250));
    expect(AppBoxKitSnackbarScrimLease.debugScrimMounted, isTrue,
        reason: 'the mid-fade re-lease must cancel the pending removal');

    unawaited(leaseB.release());
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump();
    expect(AppBoxKitSnackbarScrimLease.debugScrimMounted, isFalse);
  });
}
